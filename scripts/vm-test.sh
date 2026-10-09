#!/usr/bin/env bash
# VM Debian locale dédiée : 2 vCPU, 2048 Mo, disque qcow2 extensible de 12 Go.
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
dir="$root/.vm-test"
key="/tmp/vmra-$(printf '%s' "$root" | sha256sum | cut -c1-12).key"
action="${1:-status}"
mkdir -p "$dir"

ssh_vm() {
    install -m 600 "$dir/id_ed25519" "$key"
    ssh -i "$key" -p 22222 -o BatchMode=yes -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$dir/known_hosts" \
        root@127.0.0.1 "$@"
}
vm_running() {
    [ -f "$dir/qemu.pid" ] || return 1
    local pid
    pid=$(cat "$dir/qemu.pid")
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    [ -r "/proc/$pid/cmdline" ] || return 1
    grep -Fq -- "$dir/debian-test.qcow2" "/proc/$pid/cmdline"
}

case "$action" in
    start)
        if vm_running; then echo "VM déjà démarrée."; exit 0; fi
        [ -f "$dir/debian-base.qcow2" ] || {
            echo "Téléchargez l'image Debian officielle et vérifiez SHA512 (voir GUIDE-DEBIAN-VIERGE.md)." >&2
            exit 1
        }
        if [ ! -f "$dir/id_ed25519" ]; then
            ssh-keygen -q -t ed25519 -N '' -f "$dir/id_ed25519"
        fi
        if [ ! -f "$dir/debian-test.qcow2" ]; then
            qemu-img create -f qcow2 -F qcow2 -b "$dir/debian-base.qcow2" "$dir/debian-test.qcow2" 12G
        fi
        pub=$(cat "$dir/id_ed25519.pub")
        cat > "$dir/user-data" <<EOF
#cloud-config
hostname: vmra-debian-test
disable_root: false
ssh_pwauth: false
users:
  - name: root
    ssh_authorized_keys:
      - $pub
growpart:
  mode: auto
  devices: ['/']
resize_rootfs: true
EOF
        printf 'instance-id: vmra-debian-test\nlocal-hostname: vmra-debian-test\n' > "$dir/meta-data"
        cloud-localds "$dir/seed.img" "$dir/user-data" "$dir/meta-data"
        qemu-system-x86_64 -name vmra-debian-test -enable-kvm -cpu host -smp 2 -m 2048 \
            -drive "file=$dir/debian-test.qcow2,format=qcow2,if=virtio,discard=unmap" \
            -drive "file=$dir/seed.img,format=raw,if=virtio,readonly=on" \
            -netdev user,id=net0,hostfwd=tcp:127.0.0.1:22222-:22,hostfwd=tcp:127.0.0.1:8443-:443,hostfwd=tcp:127.0.0.1:33001-:3001 \
            -device virtio-net-pci,netdev=net0 \
            -display none -serial "file:$dir/serial.log" -monitor none \
            -pidfile "$dir/qemu.pid" -daemonize
        echo "VM démarrée : 2 Go / 2 vCPU. Dashboard https://localhost:8443 ; agents https://localhost:33001"
        ;;
    deploy)
        vm_running || { echo "Démarrez la VM d'abord." >&2; exit 1; }
        tar -C "$root" --exclude=.vm-test --exclude=.env --exclude=backups \
            -czf - . | ssh_vm 'mkdir -p /opt/vmra-src && tar -xzf - -C /opt/vmra-src'
        if [ -f "$root/.env" ]; then
            ssh_vm 'umask 077; mkdir -p /opt/multi-agents; cat > /opt/multi-agents/.env' < "$root/.env"
        fi
        reuse="${REUSE_IMAGE:-0}"
        [[ "$reuse" == 0 || "$reuse" == 1 ]] || exit 2
        ssh_vm "env ALLOW_NO_API_KEY=1 HOSTNAME_PUBLIQUE=localhost SWAP_MB=1024 NONINTERACTIVE=1 NOTUI=1 FORCE_ACTION=install REUSE_IMAGE=$reuse bash /opt/vmra-src/setup.sh"
        ssh_vm 'sed -i s/:3001/:33001/g /opt/multi-agents/dashboard/index.html'
        ;;
    ssh)
        shift
        ssh_vm "$@"
        ;;
    status)
        if ! vm_running; then echo "VM arrêtée."; exit 0; fi
        du -h "$dir/debian-base.qcow2" "$dir/debian-test.qcow2"
        ssh_vm 'cat /etc/debian_version; uname -m; free -m; df -h /; cd /opt/multi-agents && docker compose ps && docker stats --no-stream'
        ;;
    stop)
        if vm_running; then ssh_vm 'shutdown -h now'; else echo "VM déjà arrêtée."; fi
        ;;
    remove)
        vm_running && { echo "Arrêtez la VM avant de la supprimer." >&2; exit 1; }
        # Le chemin absolu est dérivé de la racine de ce script et contrôlé avant
        # toute suppression. Les sources et autres VM ne sont jamais ciblées.
        [ "$(realpath "$dir")" = "$root/.vm-test" ] || exit 1
        rm -f -- "$dir/debian-test.qcow2" "$dir/debian-base.qcow2" \
            "$dir/debian-test.compact.qcow2" \
            "$dir/seed.img" "$dir/id_ed25519" "$dir/id_ed25519.pub" \
            "$dir/user-data" "$dir/meta-data" "$dir/known_hosts" "$dir/qemu.pid" "$key"
        echo "Disques et clés de la VM supprimés. Sources et rapports conservés."
        ;;
    *) echo "Usage: $0 {start|deploy|ssh|status|stop|remove}" >&2; exit 2 ;;
esac
