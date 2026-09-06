#!/usr/bin/env bash
set -euo pipefail

# 1. Автоматическое вычисление корня репозитория относительно скрипта
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$SCRIPT_DIR"

# 2. Подгрузка параметров из .env (если файл существует)
if [ -f "$BASE_DIR/.env" ]; then
  # Экспортируем переменные без вывода секретов
  set -a
  source "$BASE_DIR/.env"
  set +a
fi

# 3. Дефолтные значения на случай отсутствия в .env
SSH_USER="${VM_SSH_USER:-ubuntu}"
SSH_KEY="${VM_SSH_KEY_PATH:-$HOME/.ssh/yandex_vm}"

STAGE_DIR="$BASE_DIR/terraform/environments/stage"
INV_DIR="$BASE_DIR/kubespray/inventory/mycluster"
INV_FILE="$INV_DIR/hosts.yaml"

echo "==> Рабочая директория проекта: $BASE_DIR"
echo "==> Чтение outputs из Terraform State..."
cd "$STAGE_DIR"

if ! terraform output > /dev/null 2>&1; then
  echo "Ошибка: Terraform outputs недоступны. Убедитесь, что terraform apply был выполнен." >&2
  exit 1
fi

MASTER_PUB=$(terraform output -raw k8s_master_public_ip)
MASTER_INT=$(terraform output -raw k8s_master_internal_ip)
WORKER1_INT=$(terraform output -json k8s_workers_internal_ips | jq -r '."worker-01"')
WORKER2_INT=$(terraform output -json k8s_workers_internal_ips | jq -r '."worker-02"')

echo "  Master Public IP:     $MASTER_PUB"
echo "  Master Internal IP:   $MASTER_INT"
echo "  Worker-01 IP:         $WORKER1_INT"
echo "  Worker-02 IP:         $WORKER2_INT"
echo "  SSH User:             $SSH_USER"
echo "  SSH Key:              $SSH_KEY"

# Создание каталога инвентаря, если ещё не существует
mkdir -p "$INV_DIR"

echo "==> Формирование $INV_FILE..."
cat <<YAML > "$INV_FILE"
all:
  hosts:
    node1:
      ansible_host: $MASTER_PUB
      ip: $MASTER_INT
      access_ip: $MASTER_INT
      ansible_user: $SSH_USER
      ansible_ssh_private_key_file: $SSH_KEY
    node2:
      ansible_host: $WORKER1_INT
      ip: $WORKER1_INT
      access_ip: $WORKER1_INT
      ansible_user: $SSH_USER
      ansible_ssh_private_key_file: $SSH_KEY
      ansible_ssh_common_args: '-o ProxyJump=$SSH_USER@$MASTER_PUB -o IdentityFile=$SSH_KEY -o StrictHostKeyChecking=no'
    node3:
      ansible_host: $WORKER2_INT
      ip: $WORKER2_INT
      access_ip: $WORKER2_INT
      ansible_user: $SSH_USER
      ansible_ssh_private_key_file: $SSH_KEY
      ansible_ssh_common_args: '-o ProxyJump=$SSH_USER@$MASTER_PUB -o IdentityFile=$SSH_KEY -o StrictHostKeyChecking=no'
  children:
    kube_control_plane:
      hosts:
        node1:
    kube_node:
      hosts:
        node2:
        node3:
    etcd:
      hosts:
        node1:
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {}
YAML

echo "==> Инвентарь успешно сгенерирован в $INV_FILE"