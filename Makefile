SHELL := /bin/bash

# Используем абсолютный путь к .env через $(CURDIR)
ENV_LOAD := $(if $(wildcard .env),set -a; source $(CURDIR)/.env; set +a;,true;)

# Репозиторий приложения по умолчанию (переопределяется из .env)
APP_REPO ?= Dogafas/dip-app

.PHONY: all check-deps fetch-kubespray init-venv infra-up k8s-up apps-up up down clean

VENV_DIR := kubespray/venv
export ANSIBLE_CONFIG := $(CURDIR)/kubespray/ansible.cfg

up: check-deps init-venv infra-up k8s-up apps-up
	@echo "========================================="
	@echo "Кластер и приложения успешно развернуты!"
	@echo "========================================="

check-deps:
	@echo "Проверка зависимостей..."
	@which terraform >/dev/null || (echo "Ошибка: terraform не установлен" && exit 1)
	@which helm >/dev/null || (echo "Ошибка: helm не установлен" && exit 1)
	@which kubectl >/dev/null || (echo "Ошибка: kubectl не установлен" && exit 1)
	@which nc >/dev/null || (echo "Ошибка: netcat (nc) не установлен" && exit 1)
	@which git >/dev/null || (echo "Ошибка: git не установлен" && exit 1)
	@which python3 >/dev/null || (echo "Ошибка: python3 не установлен" && exit 1)

KUBESPRAY_VERSION := release-2.24

fetch-kubespray:
	@if [ ! -d "kubespray" ]; then \
		echo "Скачивание официального Kubespray ($(KUBESPRAY_VERSION))..."; \
		git clone -b $(KUBESPRAY_VERSION) https://github.com/kubernetes-sigs/kubespray.git kubespray; \
		echo "Подготовка структуры инвентаря..."; \
		cp -rfp kubespray/inventory/sample kubespray/inventory/mycluster; \
	fi
	@if [ -f "ansible.cfg" ]; then \
		echo "Копирование кастомного ansible.cfg..."; \
		cp ansible.cfg kubespray/ansible.cfg; \
	fi

init-venv: fetch-kubespray
	@if [ ! -d "$(VENV_DIR)" ]; then \
		echo "Создание виртуального окружения Python..."; \
		python3 -m venv $(VENV_DIR); \
		$(VENV_DIR)/bin/pip install -U pip; \
		$(VENV_DIR)/bin/pip install -r kubespray/requirements.txt; \
	else \
		echo "Виртуальное окружение уже существует."; \
	fi

infra-up:
	@echo "Применение конфигурации Terraform..."
	@(cd terraform/environments/stage && $(ENV_LOAD) terraform init -input=false)
	@(cd terraform/environments/stage && $(ENV_LOAD) terraform apply -auto-approve)

k8s-up:
	@echo "Получение публичного IP мастера..."
	$(eval MASTER_IP := $(shell $(ENV_LOAD) cd terraform/environments/stage && terraform output -raw k8s_master_public_ip))
	@echo "Очистка старых SSH-ключей для $(MASTER_IP)..."
	@ssh-keygen -f ~/.ssh/known_hosts -R $(MASTER_IP) 2>/dev/null || true
	@echo "Ожидание доступности SSH на $(MASTER_IP)..."
	@until nc -z -v -w5 $(MASTER_IP) 22 2>/dev/null; do echo "Ждем SSH..."; sleep 3; done
	@echo "Генерация инвентаря..."
	$(ENV_LOAD) ./generate_inventory.sh
	@echo "Запуск Kubespray..."
	$(ENV_LOAD) bash -c "source $(VENV_DIR)/bin/activate && cd kubespray && ansible-playbook -i inventory/mycluster/hosts.yaml --become --become-user=root cluster.yml -e 'download_retries=10' -e 'download_timeout=60'"
	@echo "Синхронизация kubeconfig..."
	$(ENV_LOAD) ./generate_inventory.sh

apps-up:
	@echo "Ожидание готовности узлов Kubernetes..."
	@kubectl wait --for=condition=Ready nodes --all --timeout=300s
	@echo "Синхронизация секретов в GitHub Actions ($(APP_REPO))..."
	@if which gh >/dev/null 2>&1; then \
		echo "  -> Обновление KUBE_CONFIG..."; \
		gh secret set KUBE_CONFIG -R $(APP_REPO) --body "$$(cat ~/.kube/config | base64 -w 0)" 2>/dev/null || true; \
		if [ -n "$$DOCKERHUB_USERNAME" ]; then \
			echo "  -> Обновление DOCKERHUB_USERNAME..."; \
			gh secret set DOCKERHUB_USERNAME -R $(APP_REPO) --body "$$DOCKERHUB_USERNAME" 2>/dev/null || true; \
		fi; \
		if [ -n "$$DOCKERHUB_TOKEN" ]; then \
			echo "  -> Обновление DOCKERHUB_TOKEN..."; \
			gh secret set DOCKERHUB_TOKEN -R $(APP_REPO) --body "$$DOCKERHUB_TOKEN" 2>/dev/null || true; \
		fi; \
	else \
		echo "Предупреждение: gh cli не найден или не авторизован. Обновите секреты в GitHub вручную."; \
	fi
	@echo "Актуализация IP-адресов в манифестах..."
	$(eval MASTER_IP := $(shell $(ENV_LOAD) cd terraform/environments/stage && terraform output -raw k8s_master_public_ip))
	@sed -i "s/app\.[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\.nip\.io/app.$(MASTER_IP).nip.io/g" k8s/app/app.yaml
	@sed -i "s/grafana\.[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\.nip\.io/grafana.$(MASTER_IP).nip.io/g" k8s/monitoring/values.yaml
	@echo "Обновление репозиториев Helm..."
	@helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
	@helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
	@helm repo update
	@echo "Установка Ingress Controller..."
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