## Отчет о выполнении дипломного практикума в Yandex.Cloud

### Тема: Развертывание отказоустойчивого Kubernetes-кластера в Yandex Cloud, мониторинг и организация сквозного CI/CD пайплайна

#### Ссылки на репозитории проекта

- [Инфраструктура, манифесты и оркестрация](https://github.com/Dogafas/dip-ops)

- [Исходный код приложения и CI/CD Pipeline](https://github.com/Dogafas/dip-app)

- [Реестр контейнеров Docker Hub](https://hub.docker.com/r/datadynamo/dip-app)

#### 1. *Создание облачной инфраструктуры (Terraform)*

Инфраструктура спроектирована с использованием принципов **Infrastructure as Code (IaC)** с помощью Terraform в соответствии с требованиями оптимизации расходов и обеспечения сетевой изоляции:

1. **Сервисный аккаунт и S3-бэкенд:** Создана конфигурация для подготовки сервисного аккаунта с минимально необходимыми правами и Object Storage Bucket для безопасного удаленного хранения стейт-файла (`terraform.tfstate`).

2. **Сетевой контур (VPC):** Развернута виртуальная сеть с 3 подсетями в изолированных зонах доступности Yandex Cloud (`ru-central1-a`, `ru-central1-b`, `ru-central1-d`).

3. **Вычислительные ресурсы (Compute Cloud):**

   - **Мастер-узел** (`node1`): Выделен публичный IP-адрес для администрирования, доступа к API-серверу Kubernetes (6443) и маршрутизации входящего HTTP-трафика.

   - **Рабочие узлы** (`node2`, `node3`): Размещены в приватных подсетях без прямого доступа из Интернета. Для минимизации бюджета воркеры настроены как прерываемые виртуальные машины (`preemptible`).

   - **Маршрутизация и шлюз:** Выход рабочих узлов во внешнюю сеть для загрузки пакетов и Docker-образов организован через централизованный NAT Gateway.

4. **Воспроизводимость:** Процесс автоматизирован — команды `terraform apply` и `terraform destroy` выполняются без ручных вмешательств через унифицированный `Makefile`.

#### 2. *Создание Kubernetes-кластера (Kubespray / Ansible)*

Развертывание кластера выполнено с помощью официального инструментария **Kubespray:**

1. **Портативность и автономия:** Репозиторий `dip-ops` спроектирован полностью независимым. При вызове команды `make up` скрипт автоматически скачивает стабильный релиз Kubespray (`release-2.24`), разворачивает изолированное виртуальное окружение Python (`venv`), устанавливает зависимости и применяет кастомный `ansible.cfg`.

2. **Сетевой доступ и инвентарь:** Скрипт `generate_inventory.sh` считывает выходные параметры Terraform State, динамически генерирует `inventory/mycluster/hosts.yaml` с туннелированием через мастер (`ProxyJump`), настраивает CNI **Calico** и выгружает актуальный `~/.kube/config`.

3. **Результат:**

   - Кластер версии `v1.28.10` с рантаймом `containerd://1.7.22`.

   - Все узлы (`node1`, `node2`, `node3`) находятся в статусе `Ready`.

   - Команда `kubectl get pods -A` подтверждает бессбойную работу системных компонентов (`calico`, `coredns`, `kube-apiserver`, `nodelocaldns`).

#### 3. *Создание тестового приложения*

1. В репозитории [dip-app](https://github.com/Dogafas/dip-app) подготовлено легковесное веб-приложение на базе веб-сервера Nginx Alpine, отдающее статическую HTML-страницу.

2. Разработан оптимизированный многоэтапный [Dockerfile](https://github.com/Dogafas/dip-app/blob/main/Dockerfile).

3. Публикация артефактов автоматизирована в публичном реестре *Docker Hub*: [datadynamo/dip-app](https://hub.docker.com/repository/docker/datadynamo/dip-app/general). Все релизы версионируются в соответствии с SemVer.

#### 4. *Подготовка системы мониторинга и деплой приложения*

В кластер развернут комплексный стек наблюдаемости и входящей маршрутизации:

1. **NGINX Ingress Controller:**

   - Установлен через Helm-чарт в неймспейс `ingress-nginx`.

   - Развернут в режиме `hostNetwork: true` на мастер-узле, что позволило принимать входящие HTTP-соединения напрямую на 80 порту мастера без необходимости использования дорогостоящего внешнего облачного балансировщика.

2. **Деплой тестового приложения ([dip-app](https://github.com/Dogafas/dip-app)):**

   - Развернут Deployment (2 реплики) с распределением по рабочим нодам `node2` и `node3` через `nodeAffinity`, сервис `ClusterIP` и правило Ingress.
  
   - Адресация настроена через wildcard DNS-сервис [nip.io](https://nip.io): `http://app.<MASTER_IP>.nip.io`.

3. **Стек мониторинга (kube-prometheus-stack):**

   - Установлен оператор kube-prometheus-stack от сообщества prometheus-community.
  
   - Автоматически развернуты и сконфигурированы: Prometheus, Alertmanager, Node Exporter (сбор метрик со всех узлов ВМ) и Grafana.
  
   - Веб-интерфейс Grafana опубликован на 80 порту по адресу **`http://grafana.<MASTER_IP>.nip.io`** с учетными данными:

     - Логин: `admin`

     - Пароль: `prom-operator`

   - Доступны стандартные дашборды мониторинга кластера: *Kubernetes / Compute Resources / Cluster и Node Exporter / Nodes*.

#### 5. *Установка и настройка CI/CD конвейера (GitHub Actions)*

В репозитории [dip-app](https://github.com/Dogafas/dip-app) настроен сквозной конвейер непрерывной интеграции и доставки (`.github/workflows/ci-cd.yml`):

1. **Этап CI (коммит в ветку / PR):**

   - Запуск Docker Buildx.

   - Безопасная аутентификация в Docker Hub по токену (`DOCKERHUB_TOKEN`).

   - Сборка и push тестового образа с временными тегами коммита/ветки.

2. **Этап CD (публикация Git-тега `v*.*.*`):**

   - Извлечение версии релиза и автоматическое приведение тега к формату SemVer.

   - Сборка и публикация неизменяемого релизного образа (например, `datadynamo/dip-app:1.0.7`).

   - Получение актуального секрета `KUBE_CONFIG`, подключение к API-серверу Kubernetes.

   - Выполнение команды `kubectl set image deployment/dip-app ...` и отслеживание статуса `kubectl rollout status` (бесшовное плавное обновление подов методом RollingUpdate без простоя).

3. **Автоматическая синхронизация секретов:**

   - В цель `apps-up` корневого `Makefile` интегрирована утилита GitHub CLI (`gh`). При каждом пересоздании кластера или смене рабочего места новый публичный IP мастера и свежие TLS-сертификаты автоматически перекодируются в Base64 и перезаписывают секрет `KUBE_CONFIG` в репозитории [dip-app](https://github.com/Dogafas/dip-app) без участия человека.

#### 6. *Демонстрация и ссылки для проверки*

| Компонент | Ссылка / Команда | Данные доступа / Статус |
| ---- | ---- | ---- |
|    Репозиторий dip-ops  |   [github.com/Dogafas/dip-ops](https://github.com/Dogafas/dip-ops)   |  IaC, Kubespray, Ingress, Monitoring    |
|   Репозиторий dip-app   |  [github.com/Dogafas/dip-app](github.com/Dogafas/dip-app)    |    Исходный код, Dockerfile, GitHub Actions  |
|Реестр Docker Hub | [hub.docker.com/r/datadynamo/dip-app](hub.docker.com/r/datadynamo/dip-app) | Релизные теги 1.0.0 — 1.0.5
| Тестовое приложение |`http://app.<MASTER_IP>.nip.io/`|HTTP/1.1 200 OK |
|Панель Grafana |`http://grafana.<MASTER_IP>.nip.io/` | Логин: `admin` / Пароль: `prom-operator` |
|Полный запуск проекта |`make up` |Автоматический подъем всей инфраструктуры с нуля |
|Уничтожение ресурсов |`make down` |Полная очистка облака для экономии ресурсов |

#### 7. *Скриншоты*


#### 8. *Настройка CI/CD в GitHub Actions*

## Настройка CI/CD в GitHub Actions

Пайплайн использует GitHub Actions для автоматической сборки Docker-образа и доставки в кластер Kubernetes при публикации релизных Git-тегов (`v*.*.*`).

Для работы пайплайна в настройках репозитория (`Settings -> Secrets and variables -> Actions`) должны быть заданы следующие Repository Secrets:

| Секрет | Описание |
| :--- | :--- |
| `DOCKERHUB_USERNAME` | Имя пользователя в реестре Docker Hub |
| `DOCKERHUB_TOKEN` | Personal Access Token с правами Read & Write из Docker Hub |
| `KUBE_CONFIG` | Содержимое `~/.kube/config` кластера в кодировке Base64 (`cat ~/.kube/config \| base64 -w 0`) |

> **Примечание:** Если вы форкаете проект под своей учетной записью, убедитесь, что в переменной окружения `IMAGE_NAME` файла `.github/workflows/ci-cd.yml` указано ваше пространство имен на Docker Hub.
