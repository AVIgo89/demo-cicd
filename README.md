# Проект: полный цикл сборки-поставки приложения с использованием практик CI/CD.

Приложение — HTTP-сервер на Go, отдающий версию сборки. Разворачивается в Kubernetes-кластер (k3s) на виртуальной машине Yandex Cloud. Сборка, тестирование и публикация Docker-образа выполняются в GitHub Actions. Деплой в кластер — через Helm по тегу. Мониторинг и логирование — Prometheus, Grafana, Loki, Promtail.

**Ссылки:**

- Репозиторий: https://github.com/AVIgo89/demo-cicd
- GitHub Actions: https://github.com/AVIgo89/demo-cicd/actions
- Container Registry (ghcr.io): https://github.com/users/AVIgo89/packages/container/demo-cicd
- Приложение: http://demo.51.250.86.208.nip.io
- Grafana: http://grafana.51.250.86.208.nip.io (admin / admin12345)
- Yandex Cloud Console: https://console.yandex.cloud
- k3s: https://k3s.io
- kube-prometheus-stack: https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack
- Loki Stack: https://github.com/grafana/helm-charts/tree/main/charts/loki-stack
- Traefik: https://traefik.io

---

## 1. Устройство репозитория

| Путь | Назначение |
|---|---|
| `main.go` | Исходный код приложения (HTTP-сервер на Go, эндпоинты `/` и `/health`) |
| `main_test.go` | Юнит-тесты приложения |
| `go.mod` | Зависимости Go-модуля |
| `Dockerfile` | Многостадийная сборка Docker-образа (builder + alpine runtime) |
| `.dockerignore` | Исключения для контекста Docker-сборки |
| `helm/demo/` | Helm-чарт приложения |
| `helm/demo/Chart.yaml` | Метаданные чарта (`version`, `appVersion`) |
| `helm/demo/values.yaml` | Значения по умолчанию (образ, реплики, ingress, ресурсы) |
| `helm/demo/templates/deployment.yaml` | Deployment приложения |
| `helm/demo/templates/service.yaml` | Service (ClusterIP, порт 80 → 8080) |
| `helm/demo/templates/ingress.yaml` | Ingress (Traefik, хост `demo.51.250.86.208.nip.io`) |
| `helm/demo/templates/_helpers.tpl` | Вспомогательные шаблоны Helm |
| `terraform/` | IaC: создание инфраструктуры в Yandex Cloud |
| `terraform/versions.tf` | Версии Terraform и провайдера, S3-бэкенд для state |
| `terraform/variables.tf` | Переменные (cloud_id, folder_id, zone, ssh_public_key) |
| `terraform/main.tf` | VPC, подсеть, security group, статический IP, ВМ с cloud-init |
| `terraform/cloud-init.yaml` | Скрипт первичной настройки ВМ (установка k3s) |
| `terraform/terraform.tfvars` | Значения переменных (**не коммитится**, в `.gitignore`) |
| `terraform/key.json` | Ключ сервисного аккаунта (**не коммитится**, в `.gitignore`) |
| `monitoring/grafana-ingress.yaml` | Ingress для Grafana (хост `grafana.51.250.86.208.nip.io`) |
| `.github/workflows/ci.yaml` | CI: тесты, сборка бинарника, публикация Docker-образа в ghcr.io |
| `.github/workflows/deploy.yaml` | CD: `helm upgrade --install` в кластер при пуше тега `v*.*.*` |
| `.gitignore` | Исключения: секреты, state, служебные файлы |
| `README.md` | Этот файл |

### Что где искать

- **CI** — `.github/workflows/ci.yaml` (тесты, сборка бинарника, публикация образа).
- **CD** — `.github/workflows/deploy.yaml` (helm upgrade по тегу).
- **IaC** — `terraform/` (VPC, подсеть, SG, IP, ВМ, cloud-init).
- **Helm** — `helm/demo/` (deployment, service, ingress).
- **Мониторинг** — `monitoring/` (ingress для Grafana) + Helm-релизы `monitoring` и `loki` в namespace `monitoring`.

В репозитории **нет** секретов: `terraform/key.json` и `terraform/terraform.tfvars` исключены через `.gitignore`, kubeconfig хранится в GitHub Secrets, статические ключи Object Storage — в переменных окружения. Подробнее — раздел 5.4.

### Git-flow

Используется упрощённый git-flow с двумя постоянными ветками:

- **`main`** — прод. Защищена branch protection: требуется PR, минимум 1 approve, зелёный CI (`build-test`).
- **`develop`** — интеграция. Сюда мержатся feature-ветки. Защищена: требуется PR, зелёный CI.

Жизненный цикл:

1. Фича → ветка `feat/<название>` от `develop` → PR в `develop` → мерж.
2. Релиз → PR `develop → main` → мерж → тег `vX.Y.Z` **на `main`** → пуш тега.
3. Хотфикс → ветка `hotfix/<название>` от `main` → PR в `main` → мерж → тег `vX.Y.(Z+1)` → мерж-бэк в `develop`.

Прямой пуш в `main` и `develop` запрещён (кроме администратора).

### Соглашение о коммитах (Conventional Commits)

- `feat: ...` — новая функциональность;
- `fix: ...` — багфикс;
- `chore: ...` — рутина (обновление зависимостей, `.gitignore`);
- `ci: ...` — изменения в workflow;
- `docs: ...` — документация;
- `refactor: ...` — рефакторинг без изменения поведения.

---

## 2. Приложение

HTTP-сервер на Go, два эндпоинта:

- `GET /` — возвращает `Hello from demo-cicd! Version: <APP_VERSION>`.
- `GET /health` — возвращает `OK` (используется для readiness/liveness проб Kubernetes).

Переменная окружения `APP_VERSION` прокидывается из Helm-чарта (`values.appVersion`), чтобы в ответе была версия релиза.

Сборка: `go build -ldflags="-s -w" -o app .`
Тесты: `go test ./...`

---

## 3. CI/CD

### 3.1. CI (`.github/workflows/ci.yaml`)

Запускается на:
- push в `main` и `develop`;
- pull request в `main` и `develop`;
- push тега `v*.*.*`.

Шаги job **`build-test`**:

1. Checkout.
2. Установка Go 1.22.
3. `go test ./...`.
4. `go build -o app .`.
5. Публикация бинарника как artifact (`actions/upload-artifact`).

Шаги job **`docker`** (только на тег `v*.*.*`, после успешного `build-test`):

1. Checkout.
2. Логин в `ghcr.io` через `GITHUB_TOKEN`.
3. Генерация тегов (`docker/metadata-action`): `vX.Y.Z` и `latest`.
4. `docker/build-push-action` — сборка и пуш образа в ghcr.io.

Образы хранятся в GitHub Container Registry:

- `ghcr.io/avigo89/demo-cicd:v1.0.0`
- `ghcr.io/avigo89/demo-cicd:latest`

Пакет сделан **публичным** (Package settings → Change visibility → Public), чтобы кластер мог скачивать образ анонимно.

### 3.2. CD (`.github/workflows/deploy.yaml`)

Запускается только на push тега `v*.*.*`.

Шаги:

1. Checkout.
2. Установка Helm v3.14.
3. Установка kubectl.
4. `Configure kubeconfig` — декодирует base64 из секрета `KUBECONFIG` в `~/.kube/config`.
5. `Deploy via Helm`:

   ```bash
   helm upgrade --install demo ./helm/demo \
     --namespace demo --create-namespace \
     --set image.repository=ghcr.io/avigo89/demo-cicd \
     --set image.tag=${{ github.ref_name }} \
     --set appVersion=${{ github.ref_name }} \
     --wait --timeout 5m \
     --burst-limit 300 \
     --qps 50
