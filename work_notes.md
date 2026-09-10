Команды

перед запуском команд Terraform не забыть подгрузить переменные в текущую сессию терминала (из корня проекта)

```bash
set -a
source .env
set +a
```

Проверка загрузки переменных:

```bash
echo "SA Key File: $TF_VAR_service_account_key_file"
echo "Default Zone: $TF_VAR_default_zone"
echo "AWS Key ID: $AWS_ACCESS_KEY_ID"
```

- пути и ключи должны выводиться без лишних экранированных кавычек

#### Этап 1. Базовый уровень: S3-бакет для удаленного стейта

Стейт должен быть централизованно доступен в бакете перед развертыванием любых других сред.

Перейди в каталог `dip-ops/terraform/global/s3`
   Инициализируй backend: `terraform init`

- (Если требуется перенести локальное состояние в бакет, используй флаг -migrate-state)
   Проверь план и состояние бакета: `terrafrom plan`

#### Этап 2. Проверка переиспользуемого модуля VPC

Модули не развертываются напрямую, но их синтаксис необходимо проверять.

`cd /.../.../dip-ops/terraform/modules/vpc`

Форматирование и валидация: `terraform fmt`

#### Этап 3. Развертывание окружения `stage` (Сеть и подсети)

в директории `dip-ops/terraform/environments/stage` инициализируй окружение с подключением к удаленному бэкенду и модулям: `terraform init` (Команда подключит `stage/terraform.tfstate` в бакете и проинициализирует локальный модуль `../../modules/vpc`). План изменений: `terraform plan`. При необходимости: `terraform apply`

- проверка созданных ресурсов через YC CLI:

  ```bash
  yc vpc network list
  yc vpc subnet list
  ```

Порядок действий при удалении ресурсов (Teardown)
Если потребуется полностью удалить инфраструктуру, порядок строго обратный:

`cd /.../.../.../dip-ops/terraform/environments/stage && terraform destroy` (сначала удаляются подсети и VPC, чтобы освободить зависимости).

`cd /.../.../.../dip-ops/terraform/global/s3` — переход на локальный стейт (`terraform init -migrate-state` с закомментированным `backend "s3"`) и затем `terraform destroy` (удаление корзины Object Storage).

##### Памятка для быстрого старта после перерыва

```
# 1. Поднимаем ВМ в облаке
cd /.../.../.../dip-ops/terraform/environments/stage
terraform apply --auto-approve
terraform refresh

# 2. Генерируем инвентарь
cd /.../.../.../dip-ops
./generate_inventory.sh

# 2.1 Проверка связности узлов через Ansible
cd /.../.../.../dip-ops/kubespray
source venv/bin/activate
ansible -i inventory/mycluster/hosts.yaml all -m ping

 - (Все 3 узла (node1, node2, node3) должны вернуть SUCCESS => {"ping": "pong"}.)

# 3. Раскатываем кластер (из venv)
cd kubespray
source venv/bin/activate
ansible-playbook -i inventory/mycluster/hosts.yaml --become --become-user=root cluster.yml

# 4. Скачиваем kubeconfig (скрипт сделает это автоматически)
cd /.../.../.../dip-ops
./generate_inventory.sh
```

##### Проверка / обновление секрета KUBE_CONFIG в GitHub:

- Через GitHub CLI:
```
gh secret set KUBE_CONFIG -R Dogafas/dip-app --body "$(cat ~/.kube/config | base64 -w 0)"
```