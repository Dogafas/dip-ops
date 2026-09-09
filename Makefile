SHELL := /bin/bash

# Используем абсолютный путь к .env через $(CURDIR)
ENV_LOAD := $(if $(wildcard .env),set -a; source $(CURDIR)/.env; set +a;,true;)

.PHONY: all check-deps init-venv infra-up k8s-up apps-up up down clean

VENV_DIR := kubespray/venv
export ANSIBLE_CONFIG := $(CURDIR)/kubespray/ansible.cfg

up: check-deps init-venv infra-up k8s-up apps-up
	@echo "========================================="
	@echo "Кластер и приложения успешно развернуты!"
	@echo "========================================="

check-deps:
	@echo "Проверка зависимостей..."
	@which terraform >/dev/null || (echo "Ошибка: terraform не установлен" && exit 1)
	@which ansible >/dev/null || (echo "Ошибка: ansible не установлен" && exit 1)
	@which helm >/dev/null || (echo "Ошибка: helm не установлен" && exit 1)
	@which kubectl >/dev/null || (echo "Ошибка: kubectl не установлен" && exit 1)
	@which nc >/dev/null || (echo "Ошибка: netcat (nc) не установлен" && exit 1)

init-venv:
	@if [ ! -d "$(VENV_DIR)" ]; then \
		echo "Создание виртуального окружения Python..."; \
		python3 -m venv $(VENV_DIR); \
		$(VENV_DIR)/bin/pip install -r kubespray/requirements.txt; \
	else \
		echo "Виртуальное окружение уже существует."; \
	fi

infra-up:
	@echo "Применение конфигурации Terraform..."
	# Исправлено: загружаем .env ДО перехода в папку, либо используем абсолютный путь
	@(cd terraform/environments/stage && $(ENV_LOAD) terraform init -input=false)
	@(cd terraform/environments/stage && $(ENV_LOAD) terraform apply -auto-approve)

k8s-up:
	@echo "Получение публичного IP мастера..."
	# Загружаем .env перед вызовом terraform
	$(eval MASTER_IP := $(shell $(ENV_LOAD) cd terraform/environments/stage && terraform output -raw k8s_master_public_ip))
	@echo "Очистка старых SSH-ключей для $(MASTER_IP)..."
	@ssh-keygen -f ~/.ssh/known_hosts -R $(MASTER_IP) 2>/dev/null || true
	@echo "Ожидание доступности SSH на $(MASTER_IP)..."
	@until nc -z -v -w5 $(MASTER_IP) 22 2>/dev/null; do echo "Ждем SSH..."; sleep 3; done
	@echo "Генерация инвентаря..."
	# Загружаем .env перед выполнением скрипта
	$(ENV_LOAD) ./generate_inventory.sh
	@echo "Запуск Kubespray..."
	# Исправлено: загружаем .env и активируем venv в одной команде
	$(ENV_LOAD) bash -c "source $(VENV_DIR)/bin/activate && cd kubespray && ansible-playbook -i inventory/mycluster/hosts.yaml --become --become-user=root cluster.yml -e 'download_retries=10' -e 'download_timeout=60'"
	@echo "Синхронизация kubeconfig..."
	# Загружаем .env перед выполнением скрипта
	$(ENV_LOAD) ./generate_inventory.sh

apps-up:
	@echo "Ожидание готовности узлов Kubernetes..."
	@kubectl wait --for=condition=Ready nodes --all --timeout=300s
	@echo "Обновление секрета KUBE_CONFIG в GitHub репозитории Dogafas/dip-app..."
	@which gh >/dev/null && gh secret set KUBE_CONFIG -R Dogafas/dip-app --body "$$(cat ~/.kube/config | base64 -w 0)" || echo "Внимание: gh cli не настроен, обновите KUBE_CONFIG вручную"
	@echo "Актуализация IP-адресов в манифестах..."
	# Загружаем .env перед вызовом terraform
	$(eval MASTER_IP := $(shell $(ENV_LOAD) cd terraform/environments/stage && terraform output -raw k8s_master_public_ip))
	@sed -i "s/app\.[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\.nip\.io/app.$(MASTER_IP).nip.io/g" k8s/app/app.yaml
	@sed -i "s/grafana\.[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\.nip\.io/grafana.$(MASTER_IP).nip.io/g" k8s/monitoring/values.yaml
	@echo "Обновление репозиториев Helm..."
	@helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
	@helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
	@helm repo update
	@echo "Установка Ingress Controller..."
	# Загружаем .env перед helm командами
	@(cd k8s/ingress && $(ENV_LOAD) helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace -f values.yaml)
	@echo "Развертывание приложения dip-app..."
	@(cd k8s/app && $(ENV_LOAD) kubectl apply -f app.yaml)
	@echo "Развертывание мониторинга..."
	@(cd k8s/monitoring && $(ENV_LOAD) helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace -f values.yaml)
down:
	@echo "Уничтожение облачной инфраструктуры..."
	@(cd terraform/environments/stage && $(ENV_LOAD) terraform destroy -auto-approve)

clean:
	@echo "Очистка локального окружения..."
	rm -rf $(VENV_DIR)
	rm -f ~/.kube/config