(define-module (configs hosts box)
  #:use-module (gnu services)
  #:use-module (gnu services containers)
  #:use-module (gnu services shepherd)
  #:use-module (gnu services ssh)
  #:use-module (gnu system file-systems)
  #:use-module (gnu system mapped-devices)
  #:use-module (guix gexp)
  #:use-module (rde features)
  #:use-module (rde features base)
  #:use-module (rde features system)
  #:use-module (rde features wm))


;;; Host-specific file systems

(define box-mapped-devices
  (list
   (mapped-device
    (source (uuid "a018554d-cbc6-41cd-9457-112656cd5b60"))
    (target "cryptroot")
    (type luks-device-mapping))))

(define box-file-systems
  (list
   (file-system
    (mount-point "/boot/efi")
    (device (uuid "EBAA-2487" 'fat32))
    (type "vfat"))
   (file-system
    (mount-point "/")
    (device "/dev/mapper/cryptroot")
    (type "ext4")
    (dependencies box-mapped-devices))))


;;; OCI container services
;;
;; Each compose stack is declared as a group of oci-container-configuration
;; records sharing a named network.  Secrets are passed via host-environment
;; so they are read from the running shepherd environment at start time and
;; never land in the Guix store.
;;
;; Secrets pattern: write values to /etc/box-secrets (mode 0400, owned by
;; root) and source that file in Shepherd's environment before start.
;; Example /etc/box-secrets:
;;   export POSTGRES_PASSWORD=...
;;   export NEXTCLOUD_POSTGRES_PASSWORD=...
;;   etc.
;;
;; TODO: replace oci-service-type docker backend with podman once rde
;; feature-podman or a wrapper is available.

;;; Search stack — single container, no credentials

(define %search-containers
  (list
   (oci-container-configuration
    (image "searxng/searxng:latest")
    (provision "searxng")
    (network "search-net")
    (ports '(("127.0.0.1:8888" . "8080")))
    (volumes
     (list
      ;; settings.yml is a plain-file record — fully declarative
      "/home/laszlokr/guix-config/docker/search/settings.yml:/etc/searxng/settings.yml:ro"
      "/data/docker/search/searxng:/etc/searxng/data"))
    (log-file "/var/log/searxng.log"))))

;;; AI stack — ollama + open-webui + qdrant, no credentials

(define %ai-containers
  (list
   (oci-container-configuration
    (image "ollama/ollama:latest")
    (provision "ollama")
    (network "ai-net")
    (ports '(("127.0.0.1:11434" . "11434")))
    (volumes '("/data/docker/ai/ollama:/root/.ollama"))
    (log-file "/var/log/ollama.log"))

   (oci-container-configuration
    (image "ghcr.io/open-webui/open-webui:main")
    (provision "open-webui")
    (requirement '(ollama))
    (network "ai-net")
    (ports '(("127.0.0.1:3000" . "8080")))
    (environment '(("OLLAMA_BASE_URL" . "http://ollama:11434")))
    ;; WEBUI_SECRET_KEY sourced from shepherd environment at runtime
    (host-environment '("WEBUI_SECRET_KEY"))
    (volumes '("/data/docker/ai/open-webui:/app/backend/data"))
    (log-file "/var/log/open-webui.log"))

   (oci-container-configuration
    (image "qdrant/qdrant:latest")
    (provision "qdrant")
    (network "ai-net")
    (ports '(("127.0.0.1:6333" . "6333")
             ("127.0.0.1:6334" . "6334")))
    (volumes '("/data/docker/ai/qdrant:/qdrant/storage"))
    (log-file "/var/log/qdrant.log"))))

;;; Automation stack — n8n + gotify
;;
;; TODO: WEBHOOK_URL depends on final reverse-proxy/Tailscale setup.
;; Set in /etc/box-secrets once networking is settled.

(define %automation-containers
  (list
   (oci-container-configuration
    (image "n8nio/n8n:latest")
    (provision "n8n")
    (network "automation-net")
    (ports '(("127.0.0.1:5678" . "5678")))
    (environment '(("GENERIC_TIMEZONE" . "Europe/Zurich")
                   ("TZ"               . "Europe/Zurich")))
    (host-environment '("N8N_BASIC_AUTH_USER"
                        "N8N_BASIC_AUTH_PASSWORD"
                        "WEBHOOK_URL"))
    (volumes '("/data/docker/automation/n8n:/home/node/.n8n"))
    (log-file "/var/log/n8n.log"))

   (oci-container-configuration
    (image "gotify/server:latest")
    (provision "gotify")
    (network "automation-net")
    (ports '(("127.0.0.1:8090" . "80")))
    (host-environment '("GOTIFY_DEFAULTUSER_PASS"))
    (volumes '("/data/docker/automation/gotify:/app/data"))
    (log-file "/var/log/gotify.log"))))

;;; Nextcloud stack — postgres + redis + nextcloud
;;
;; TODO: postgres readiness — oci-container-configuration requirement only
;; waits for the shepherd service to start, not for postgres to accept
;; connections.  Options:
;;   a) Add a tiny health-check shepherd service that loops until
;;      pg_isready succeeds before nextcloud starts.
;;   b) Configure nextcloud with retry logic (it retries on its own for
;;      a while on first install; less reliable for upgrades).
;;
;; TODO: redis conditional --requirepass command.  Either always enable
;; the password (recommended) or build a minimal wrapper image.

(define %nextcloud-containers
  (list
   (oci-container-configuration
    (image "postgres:16-alpine")
    (provision "nextcloud-db")
    (network "nextcloud-net")
    (environment '(("POSTGRES_DB" . "nextcloud")))
    (host-environment '("POSTGRES_USER" "POSTGRES_PASSWORD"))
    (volumes '("/data/docker/nextcloud/db:/var/lib/postgresql/data"))
    (log-file "/var/log/nextcloud-db.log"))

   (oci-container-configuration
    (image "redis:7-alpine")
    (provision "nextcloud-redis")
    (network "nextcloud-net")
    ;; Always require a password; set REDIS_PASSWORD in /etc/box-secrets
    (command '("redis-server" "--requirepass" "$(REDIS_PASSWORD)"))
    (host-environment '("REDIS_PASSWORD"))
    (volumes '("/data/docker/nextcloud/redis:/data"))
    (log-file "/var/log/nextcloud-redis.log"))

   (oci-container-configuration
    (image "nextcloud:28-apache")
    (provision "nextcloud")
    (requirement '(nextcloud-db nextcloud-redis))
    (network "nextcloud-net")
    (ports '(("127.0.0.1:8080" . "80")))
    (environment '(("POSTGRES_HOST"      . "nextcloud-db")
                   ("REDIS_HOST"         . "nextcloud-redis")
                   ("REDIS_HOST_PORT"    . "6379")))
    (host-environment '("POSTGRES_USER"
                        "POSTGRES_PASSWORD"
                        "POSTGRES_DB"
                        "NEXTCLOUD_ADMIN_USER"
                        "NEXTCLOUD_ADMIN_PASSWORD"
                        "REDIS_HOST_PASSWORD"))
    (volumes
     (list "/data/docker/nextcloud/html:/var/www/html"
           "/data/docker/nextcloud/data:/var/www/html/data"
           "/data/docker/nextcloud/config:/var/www/html/config"
           "/data/docker/nextcloud/apps:/var/www/html/custom_apps"
           "/data/docker/nextcloud/themes:/var/www/html/themes"))
    (log-file "/var/log/nextcloud.log"))))

;;; Odoo stack — postgres + odoo
;;
;; TODO: same postgres readiness issue as nextcloud.
;; TODO: long term — package odoo natively in Guix and replace this
;; container with a proper guix service-type + odoo-configuration record.
;; The odoo.conf and addons directory become plain-file / local-file in
;; the Guix store.

(define %odoo-containers
  (list
   (oci-container-configuration
    (image "postgres:16-alpine")
    (provision "odoo-db")
    (network "odoo-net")
    (environment '(("POSTGRES_DB" . "odoo")))
    (host-environment '("POSTGRES_USER" "POSTGRES_PASSWORD"))
    (volumes '("/data/docker/odoo/db:/var/lib/postgresql/data"))
    (log-file "/var/log/odoo-db.log"))

   (oci-container-configuration
    (image "odoo:18.0")
    (provision "odoo")
    (requirement '(odoo-db))
    (network "odoo-net")
    (ports '(("127.0.0.1:8069" . "8069")))
    (environment '(("HOST" . "odoo-db")
                   ("PORT" . "5432")))
    (host-environment '("USER" "PASSWORD"))
    (volumes
     (list "/data/docker/odoo/data:/var/lib/odoo"
           "/home/laszlokr/guix-config/docker/odoo/odoo.conf:/etc/odoo/odoo.conf:ro"
           "/home/laszlokr/guix-config/docker/odoo/addons:/mnt/extra-addons"))
    (log-file "/var/log/odoo.log"))))

;;; OCI feature

(define (feature-box-oci-containers)
  (define (oci-system-services config)
    (list
     (service oci-service-type
              (oci-service-configuration
               (networks
                (list
                 (oci-network-configuration (name "search-net"))
                 (oci-network-configuration (name "ai-net"))
                 (oci-network-configuration (name "automation-net"))
                 (oci-network-configuration (name "nextcloud-net"))
                 (oci-network-configuration (name "odoo-net"))))
               (containers
                (append
                 %search-containers
                 %ai-containers
                 %automation-containers
                 %nextcloud-containers
                 %odoo-containers))))))

  (feature
   (name 'box-oci-containers)
   (values '((box-oci-containers . #t)))
   (system-services-getter oci-system-services)))


;;; Host-specific features

(define-public %box-features
  (list
   (feature-host-info
    #:host-name "box"
    #:timezone "Europe/Zurich")
   (feature-file-systems
    #:file-systems box-file-systems
    #:mapped-devices box-mapped-devices)
   (feature-custom-services
    #:system-services
    (list
     (service openssh-service-type
              (openssh-configuration
               (password-authentication? #f)
               (permit-root-login 'prohibit-password)))))
   (feature-box-oci-containers)
   (feature-kanshi
    #:extra-config
    `((profile single ((output HDMI-A-1 enable)))
      (profile dual ((output HDMI-A-1 enable)
                     (output HDMI-A-2 enable)))))))
