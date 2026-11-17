#!/bin/bash
# RigVibe für Raspberry Pi (64 Bit) und sBitx – Installation
#
#   curl -fsSL https://rigvibe.de/install.sh | bash
#
# Optionen (nach "bash -s --" anhängen, z. B. curl -fsSL https://rigvibe.de/install.sh | bash -s -- --geraet):
#   --geraet        Pi als eigenständiges Funkgerät: RigVibe-Oberfläche im Vollbild statt Desktop
#   --kein-geraet   nur den RigVibe-Dienst (Weboberfläche im Netz), Desktop bleibt
#   --deinstallieren  RigVibe entfernen (Daten in ~/rigvibe-data bleiben)
#   --ja            alle Rückfragen mit Ja beantworten
#   --paket DATEI --oberflaeche DATEI   ohne Internet: Serverpaket (…-Linux-ARM64-Server.tar.gz) und Oberfläche (…-Native-ARM64) von hier
#
# Installiert nach /opt/rigvibe (Programm, aktualisiert sich selbst) und ~/rigvibe-data (Einstellungen, Logbuch).
set -euo pipefail

REPO="djamplifier/rigvibe"
DIR=/opt/rigvibe
USER_NAME="${SUDO_USER:-$USER}"
HOME_DIR="$(getent passwd "$USER_NAME" | cut -d: -f6)"
DATA="$HOME_DIR/rigvibe-data"
PORT=8095
MODE=""; YES=0; UNINSTALL=0; PAKET=""; OBERFL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --geraet) MODE=geraet ;; --kein-geraet) MODE=dienst ;; --deinstallieren) UNINSTALL=1 ;; --ja|-y) YES=1 ;;
    --paket) PAKET="$2"; shift ;; --oberflaeche) OBERFL="$2"; shift ;;
    *) echo "Unbekannte Option: $1"; exit 1 ;;
  esac
  shift
done

b() { printf '\033[1m%s\033[0m\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die() { printf '\033[31mFehler:\033[0m %s\n' "$*"; exit 1; }
frage() {   # frage "Text" -> 0 = ja
  [ "$YES" = 1 ] && return 0
  local r; read -r -p "  $1 [j/N] " r < /dev/tty || r=""
  [[ "$r" =~ ^[jJyY] ]]
}

[ "$USER_NAME" = root ] && die "Bitte als normaler Benutzer starten (nicht als root) – sudo wird bei Bedarf selbst aufgerufen."
SUDO=sudo; [ "$(id -u)" = 0 ] && SUDO=""
export DEBIAN_FRONTEND=noninteractive

# ---------- Deinstallieren ----------
if [ "$UNINSTALL" = 1 ]; then
  b "RigVibe entfernen"
  $SUDO systemctl disable --now rigvibe.service 2>/dev/null || true
  $SUDO rm -f /etc/systemd/system/rigvibe.service; $SUDO systemctl daemon-reload
  rm -f "$HOME_DIR/.config/autostart/rigvibe.desktop"
  for f in "$HOME_DIR/.config/lxsession/LXDE-pi/autostart" "$HOME_DIR/.config/autostart/sbitx.desktop"; do
    [ -f "$f.vor-rigvibe" ] && mv -f "$f.vor-rigvibe" "$f" && ok "wiederhergestellt: $f"
  done
  [ -f /etc/lightdm/lightdm.conf.vor-rigvibe ] && $SUDO mv -f /etc/lightdm/lightdm.conf.vor-rigvibe /etc/lightdm/lightdm.conf && ok "Mauszeiger/Desktop wiederhergestellt"
  $SUDO rm -rf "$DIR"
  ok "entfernt. Deine Daten liegen weiter in $DATA."
  exit 0
fi

b "RigVibe – Installation für Raspberry Pi / sBitx"

# ---------- Voraussetzungen ----------
[ "$(uname -m)" = aarch64 ] || die "RigVibe braucht ein 64-Bit-System (Raspberry Pi OS 64 Bit, aarch64). Gefunden: $(uname -m)"
. /etc/os-release 2>/dev/null || true
[ "${VERSION_CODENAME:-}" = bookworm ] || [ "${VERSION_CODENAME:-}" = trixie ] || warn "Getestet mit Raspberry Pi OS 12 (bookworm) – hier: ${PRETTY_NAME:-unbekannt}"
ok "System: ${PRETTY_NAME:-?}, $(uname -m)"

SBITX=0
if grep -qi audioinjector /proc/asound/cards 2>/dev/null; then SBITX=1; fi
[ -d "$HOME_DIR/sbitx" ] && SBITX=1
[ "$SBITX" = 1 ] && ok "sBitx erkannt (Audio Injector / sBitx-Software vorhanden)"

if [ -z "$MODE" ]; then
  if [ "$SBITX" = 1 ]; then
    b "Soll der sBitx als eigenständiges Gerät mit der RigVibe-Oberfläche starten (statt Desktop und sBitx-Software)?"
    if frage "Gerätemodus einrichten?"; then MODE=geraet; else MODE=dienst; fi
  else
    b "Soll dieser Pi als eigenständiges Gerät starten (RigVibe-Oberfläche im Vollbild statt Desktop)?"
    if frage "Gerätemodus einrichten? (nein = nur Dienst, Bedienung über den Browser im Netz)"; then MODE=geraet; else MODE=dienst; fi
  fi
fi

b "Pakete"
PKG="alsa-utils pipewire-bin pulseaudio-utils curl ca-certificates"
[ "$MODE" = geraet ] && PKG="$PKG libgl1 libegl1 libgles2"
$SUDO env DEBIAN_FRONTEND=noninteractive apt-get update -qq
$SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $PKG >/dev/null 2>&1 || die "Systempakete ließen sich nicht installieren (apt-get)"
ok "Systempakete"
# DAB+ (welle-cli) und Ton aus dem Netz (ffmpeg): freiwillig, ein Fehler hier bricht die Installation nicht ab
if $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends ffmpeg welle.io >/dev/null 2>&1; then ok "DAB+ (welle.io) und ffmpeg"; else echo "  DAB+ (welle.io) nicht installiert – später: sudo apt install welle.io ffmpeg"; fi

# ---------- neueste Version ermitteln ----------
b "Lade RigVibe"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
if [ -n "$PAKET" ]; then
  [ -f "$PAKET" ] || die "Paket $PAKET nicht gefunden"
  cp "$PAKET" "$TMP/server.tar.gz"; VER=$(basename "$PAKET" | sed -E 's/RigVibe-([0-9.]+)-.*/\1/'); SRV=lokal; NAT=""
  [ -n "$OBERFL" ] && [ -f "$OBERFL" ] && NAT=lokal
  ok "Version $VER (lokale Dateien)"
else
  API=$(curl -fsSL -H "User-Agent: RigVibe-Installer" "https://api.github.com/repos/$REPO/releases/latest") || die "Keine Verbindung zu GitHub"
  VER=$(printf '%s' "$API" | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')
  SRV=$(printf '%s' "$API" | grep -oE '"browser_download_url": *"[^"]*-Linux-ARM64-Server\.tar\.gz"' | sed -E 's/.*"(https[^"]+)"/\1/' | head -1)
  NAT=$(printf '%s' "$API" | grep -oE '"browser_download_url": *"[^"]*-Native-ARM64"' | sed -E 's/.*"(https[^"]+)"/\1/' | head -1)
  [ -n "$SRV" ] || die "Im Release $VER fehlt das Paket für den Raspberry Pi (Linux-ARM64-Server)"
  ok "Version $VER"
  curl -fL --progress-bar -o "$TMP/server.tar.gz" "$SRV"
fi
$SUDO mkdir -p "$DIR"; $SUDO chown "$USER_NAME:" "$DIR"
if [ -d "$DIR/RigVibe" ]; then rm -rf "$DIR/RigVibe-vorher"; mv "$DIR/RigVibe" "$DIR/RigVibe-vorher"; fi
tar -xzf "$TMP/server.tar.gz" -C "$DIR"
[ -x "$DIR/RigVibe/RigVibe" ] || die "Paket unvollständig"
ok "Dienst nach $DIR/RigVibe"
if [ -n "$NAT" ]; then
  mkdir -p "$DIR/oberflaeche"
  if [ "$NAT" = lokal ]; then cp "$OBERFL" "$DIR/oberflaeche/rigvibe-kiosk.neu"; else curl -fL --progress-bar -o "$DIR/oberflaeche/rigvibe-kiosk.neu" "$NAT"; fi
  chmod 755 "$DIR/oberflaeche/rigvibe-kiosk.neu"; mv -f "$DIR/oberflaeche/rigvibe-kiosk.neu" "$DIR/oberflaeche/rigvibe-kiosk"
  ok "Oberfläche nach $DIR/oberflaeche"
elif [ "$MODE" = geraet ]; then
  warn "Im Release fehlt die native Oberfläche – Gerätemodus wird übersprungen"; MODE=dienst
fi

# ---------- Rechte: GPIO, I2C, Ton, serielle Schnittstellen ----------
for g in gpio i2c spi audio dialout plugdev video input; do getent group $g >/dev/null && $SUDO usermod -aG $g "$USER_NAME"; done
if [ "$SBITX" = 1 ] && command -v raspi-config >/dev/null; then $SUDO raspi-config nonint do_i2c 0 || true; fi
ok "Benutzer $USER_NAME in den Gruppen gpio, i2c, audio, dialout"

# ---------- Dienst ----------
mkdir -p "$DATA"
$SUDO tee /etc/systemd/system/rigvibe.service >/dev/null <<EOF
[Unit]
Description=RigVibe
After=network-online.target sound.target
Wants=network-online.target

[Service]
User=$USER_NAME
Environment=WW_SERVER=1
Environment=XDG_RUNTIME_DIR=/run/user/$(id -u "$USER_NAME")
ExecStart=$DIR/RigVibe/RigVibe --port $PORT --lan --no-browser --data $DATA
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
$SUDO systemctl daemon-reload
$SUDO systemctl enable --now rigvibe.service >/dev/null 2>&1
ok "Dienst rigvibe.service läuft (Weboberfläche: http://$(hostname -I | awk '{print $1}'):$PORT)"

# warten, bis der Dienst antwortet
for i in $(seq 1 60); do curl -fs "http://127.0.0.1:$PORT/api/radios" >/dev/null 2>&1 && break; sleep 2; done

# ---------- sBitx als Gerät anlegen ----------
if [ "$SBITX" = 1 ]; then
  if ! curl -fs "http://127.0.0.1:$PORT/api/radios" | grep -q '"sdr_type": *"sbitx"'; then
    curl -fs -X POST "http://127.0.0.1:$PORT/api/radios" -H 'Content-Type: application/json' \
      -d '{"id":"sbitx","name":"sBitx","kind":"sdr","sdr_type":"sbitx","autoconnect":true,"params":""}' >/dev/null \
      && curl -fs -X POST "http://127.0.0.1:$PORT/api/radios/sbitx/connect" >/dev/null || true
    ok "sBitx als Gerät angelegt (Senden ist ab Werk aus – freischalten unter Menü → Funkgerät, experimentell)"
  fi
fi

# ---------- Gerätemodus ----------
if [ "$MODE" = geraet ]; then
  b "Gerätemodus"
  cat > "$DIR/oberflaeche/start.sh" <<EOF
#!/bin/sh
# RigVibe-Oberfläche; startet nach Absturz neu (bei schnellen Abstürzen mit Pause)
sleep 3
n=0
while true; do
  t=\$(date +%s)
  $DIR/oberflaeche/rigvibe-kiosk 127.0.0.1:$PORT
  [ \$(( \$(date +%s) - t )) -gt 60 ] && n=0 || n=\$((n+1))
  [ \$n -ge 5 ] && sleep 30 || sleep 2
done
EOF
  chmod 755 "$DIR/oberflaeche/start.sh"
  mkdir -p "$HOME_DIR/.config/autostart"
  cat > "$HOME_DIR/.config/autostart/rigvibe.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=RigVibe
Exec=$DIR/oberflaeche/start.sh
X-GNOME-Autostart-enabled=true
EOF
  # Desktop-Elemente (Leiste, Dateimanager, Bildschirmschoner) abschalten, Original sichern
  LX="$HOME_DIR/.config/lxsession/LXDE-pi/autostart"
  if [ -f /etc/xdg/lxsession/LXDE-pi/autostart ] || [ -f "$LX" ]; then
    mkdir -p "$(dirname "$LX")"; [ -f "$LX" ] && [ ! -f "$LX.vor-rigvibe" ] && cp "$LX" "$LX.vor-rigvibe"
    printf '@xset s off\n@xset -dpms\n@xset s noblank\n@xsetroot -solid black\n' > "$LX"
    ok "Desktop ausgeblendet (Sicherung: $LX.vor-rigvibe)"
  fi
  # sBitx-Software nicht mehr automatisch starten (sie belegt Codec und Oszillatoren)
  for f in "$HOME_DIR/.config/autostart/sbitx.desktop" "$HOME_DIR/.config/autostart/sBitx.desktop"; do
    [ -f "$f" ] && mv -f "$f" "$f.vor-rigvibe" && ok "Autostart der sBitx-Software abgeschaltet (zurück: --deinstallieren)"
  done
  # Mauszeiger aus (Touch-Bedienung)
  if [ -f /etc/lightdm/lightdm.conf ] && ! grep -q '^xserver-command=X -nocursor' /etc/lightdm/lightdm.conf; then
    $SUDO cp -n /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.vor-rigvibe
    $SUDO sed -i 's/^#\?xserver-command=.*/xserver-command=X -nocursor/' /etc/lightdm/lightdm.conf
    grep -q '^xserver-command=' /etc/lightdm/lightdm.conf || $SUDO sed -i '/^\[Seat:\*\]/a xserver-command=X -nocursor' /etc/lightdm/lightdm.conf
    ok "Mauszeiger ausgeblendet"
  fi
  command -v raspi-config >/dev/null && $SUDO raspi-config nonint do_boot_behaviour B4 >/dev/null 2>&1 || true   # Desktop mit automatischer Anmeldung
  ok "RigVibe-Oberfläche startet beim Einschalten"
fi

echo
b "Fertig – RigVibe $VER"
echo "  Weboberfläche im Netz:  http://$(hostname -I | awk '{print $1}'):$PORT"
[ "$MODE" = geraet ] && echo "  Gerätemodus: nach einem Neustart erscheint die RigVibe-Oberfläche (sudo reboot)."
echo "  Updates: in RigVibe unter Einstellungen → RigVibe."
echo "  Entfernen: curl -fsSL https://rigvibe.de/install.sh | bash -s -- --deinstallieren"
[ "$SBITX" = 1 ] && echo "  sBitx: Senden ist EXPERIMENTELL und ab Werk aus – keine Haftung für Schäden am Gerät."
