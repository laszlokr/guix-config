(define-module (configs users laszlokr)
  #:use-module (gnu home services shepherd)
  #:use-module (gnu home services xdg)
  #:use-module (gnu home services)
  #:use-module (gnu home services shells)
  #:use-module (gnu home-services ssh)
  #:use-module (gnu packages)
  #:use-module (gnu services)
  #:use-module (gnu services virtualization)
  #:use-module (guix channels)
  #:use-module (guix download)
  #:use-module (guix gexp)
  #:use-module (guix inferior)
  #:use-module (guix packages)
  #:use-module (rde features)
  #:use-module (rde features base)
  #:use-module (rde features emacs-xyz)
  #:use-module (rde features gnupg)
  #:use-module (rde features keyboard)
  #:use-module (rde features networking)
  #:use-module (rde features docker)
  #:use-module (rde features system)
  #:use-module (rde features xdg)
  #:use-module (rde features irc)
  #:use-module (rde features terminals)
  #:use-module (rde features shells)
  #:use-module (rde features fontutils)
  #:use-module (rde features containers)
  #:use-module (rde features virtualization)
  #:use-module (rde features presets)
  #:use-module (rde features python)
  #:use-module (rde features ssh)
  #:use-module (rde features wm)
  #:use-module (rde features web-browsers)
  #:use-module (rde features version-control)
  #:use-module (rde home services emacs)
  #:use-module (rde home services wm)
  #:use-module (rde home services shells)
  #:use-module (rde home services video)
  #:use-module (rde packages)
  #:use-module (small-guix packages compose)
  ;; #:use-module (private packages emacs)
  #:use-module (srfi srfi-1))


;;; Helpers


;;; Service extensions

(define emacs-extra-packages-service
  (simple-service
   'emacs-extra-packages
   home-emacs-service-type
   (home-emacs-extension
    (init-el
     `((with-eval-after-load 'simple
         (setq-default display-fill-column-indicator-column 80)
         (setq geiser-mode-auto-p nil)
         (setq blink-cursor-mode 1)
         (setq ytdl-command "yt-dlp")
         (dirvish-override-dired-mode)
         (add-hook 'prog-mode-hook 'display-fill-column-indicator-mode))
       (setq copyright-names-regexp
             (format "%s <%s>" user-full-name user-mail-address))
       (add-hook 'after-save-hook (lambda () (copyright-update nil nil)))))
    (elisp-packages
     (append
      (list
       ;; (specification->package "emacs-dash@20240510.1327")
       ;; (specification->package "emacs-minions@1.0.2")
       ;; (specification->package "emacs-magit@20241023.1526")
       ;; (specification->package "emacs-magit-popup@20200719.1015")
       ;; (specification->package "emacs-vterm@20240825.133")
       ;; (specification->package "emacs-consult@1.8")
       )
      (strings->packages
       "emacs-piem"
       "emacs-ox-haunt"
       "emacs-rainbow-mode"
       "emacs-hl-todo"
       "emacs-yasnippet"
       ;;"emacs-consult-dir"
       "emacs-all-the-icons-completion" "emacs-all-the-icons-dired"
       "emacs-kind-icon"
       "emacs-nginx-mode" "emacs-yaml-mode"
       "emacs-ytdl"
       "emacs-minimap"
       "emacs-dirvish"
       "emacs-org-caldav"
       "emacs-calfw"
       "emacs-frames-only-mode"
       "emacs-multi-vterm"
       "emacs-ef-themes"
       "emacs-disk-usage"
       "emacs-org-roam-ui"
       "emacs-ellama"
       "emacs-emms"
       "emacs-guix"
       "emacs-org-jira"
       "emacs-org-web-tools"
       "emacs-forge"
       "emacs-dracula-theme"
       "emacs-restart-emacs"
       "emacs-org-present"))))))

(define home-extra-packages-service
  (simple-service
   'home-profile-extra-packages
   home-profile-service-type
   (append
    (strings->packages
     ;; utils
     "figlet"
     "alsa-utils" "yt-dlp"
     "pavucontrol" "wev" "cmus"
     "imagemagick"
     "recutils" "binutils" "make" "gdb"
     "gvfs" "unzip"
     "jq" "ncdu"
     "btop"
     "ripgrep" "curl"

     ;; virt
     "libvirt" "virt-manager"
     "docker-compose"

     ;; guile
     "guile-next" "guile-ares-rs" "emacs-arei"
     "haunt" "emacs-ox-haunt"

     ;; browsers
     "firefox" "nyxt"
     "icedove"

     ;; office
     "libreoffice"

     ;; misc
     "nix"
     "obs"
     "keepassxc" "nextcloud-client"
     "gthumb"
     "kicad" "openscad"
     "steam"

     ;;themes
     "hicolor-icon-theme" "adwaita-icon-theme" "gnome-themes-extra"
     "arc-theme"

     ;; files
     "thunar" "fd"))))

(define sway-extra-config-service
  (simple-service
   'sway-extra-config
   home-sway-service-type
   `((output HDMI-A-1 pos 0 0 res 1920x1080)
     (output HDMI-A-2 pos 1920 0 res 3840x2160)
     ,@(map (lambda (x) `(workspace ,x output HDMI-A-2)) (iota 8 1))

     ;; (workspace 9 output DP-2)
     ;; (workspace 10 output DP-2)

     ;; (bindswitch --reload --locked lid:on exec /run/setuid-programs/swaylock)

     (bindsym
      --locked $mod+Shift+t exec
      ,(file-append (@ (gnu packages music) playerctl) "/bin/playerctl")
      play-pause)

     (bindsym
      --locked $mod+Shift+n exec
      ,(file-append (@ (gnu packages music) playerctl) "/bin/playerctl")
      next)

     ;; vim keys
     (bindsym $mod+h focus left)
     (bindsym $mod+j focus down)
     (bindsym $mod+k focus up)
     (bindsym $mod+l focus right)
     (bindsym $mod+Ctrl+h move left)
     (bindsym $mod+Ctrl+j move down)
     (bindsym $mod+Ctrl+k move up)
     (bindsym $mod+Ctrl+l move right)
     (bindsym $mod+Shift+o workspace prev)
     (bindsym $mod+Shift+p workspace next)
     (bindsym $mod+Ctrl+o move workspace prev, workspace prev)
     (bindsym $mod+Ctrl+p move workspace next, workspace next)
     (bindsym $mod+Ctrl+b splith)
     (bindsym $mod+Ctrl+v splitv)
     (bindsym $mod+Ctrl+s layout stacking)
     (bindsym $mod+Ctrl+w layout tabbed)
     (bindsym $mod+Ctrl+y layout toggle split)
     (mode "'resize' {
        bindsym h resize shrink width 10px
        bindsym j resize grow height 10px
        bindsym k resize shrink height 10px
        bindsym l resize grow width 10px
        bindsym Return mode "default"
        bindsym Escape mode "default"
        }")
     (bindsym $mod+Ctrl+r mode "resize")
     (bindsym $mod+space exec $menu)
     ;; colors
     (client.focused          "#A4B9EF     #332E41     #E5B4E2     #DADAE8     #A4B9EF")
     (client.focused_inactive "#A4B9EF     #332E41     #E5B4E2     #DADAE8     #A4B9EF")
     (client.unfocused        "#A4B9EF     #1E1E28     #DADAE8     #DADAE8     #575268")
     (client.urgent           "#A4B9EF     #575268     #EBDDAA     #DADAE8     #EBDDAA")
     (input type:touchpad
            ;; TODO: Move it to feature-sway or feature-mouse?
            (;; (natural_scroll enable)
             (tap enabled)))

     ;; (xwayland disable)
     (bindsym $mod+Shift+Return exec "emacsclient -c --eval '(multi-vterm)'")
     ;;(bindsym $mod+Shift+Return exec "emacsclient -c --eval '(multi-vterm)'" floating enable)
     )))

(define (feature-additional-services)
  (feature-custom-services
   #:feature-name-prefix 'laszlokr
   #:home-services
   (list
    emacs-extra-packages-service
    home-extra-packages-service
    sway-extra-config-service)))

;;; User-specific features with personal preferences

;; Initial user's password hash will be available in store, so use this
;; feature with care (display (crypt "hi" "$6$abc"))

(define virtualization-features
  (list
   (feature-qemu)))

(define general-features
  (append
   rde-base
   rde-desktop
   rde-cli
   rde-emacs))

(define %all-features
  (append
   virtualization-features
   general-features))

(define nonguix-pub (local-file "../../../files/keys/nonguix-key.pub"))

(define all-features-with-custom-kernel-and-substitutes
  (append
   ;; "C-h S" (info-lookup-symbol), "C-c C-d C-i" (geiser-doc-look-up-manual)
   ;; to see the info manual for a particular function.

   ;; Here we basically remove all the features which has feature name equal
   ;; to either 'base-services or 'kernel.
   (remove (lambda (f) (member (feature-name f) '(base-services
                                                  xdg
                                                  ssh
                                                  gnupg
						  kernel
                                                  docker
                                                  irc
                                                  fonts
                                                  waybar
                                                  git)))
           %all-features)
   (list
    (feature-fonts
     #:default-font-size 16)
    (feature-git #:sign-commits? #f)
    (feature-ssh #:ssh-agent? #t)
    (feature-kernel
     #:kernel (@ (nongnu packages linux) linux)
     #:firmware (list (@ (nongnu packages linux) linux-firmware)))
    (feature-base-services
     #:guix-authorized-keys (list nonguix-pub)
     #:default-substitute-urls (list "https://bordeaux.guix.gnu.org"
                                     "https://ci.guix.gnu.org"
                                     "https://substitutes.nonguix.org")))))

(define-public %laszlokr-features
  (append
   all-features-with-custom-kernel-and-substitutes
   (list
    (feature-additional-services)
    (feature-user-info
     #:user-name "laszlokr"
     #:full-name "Laszlo Krajnikovszkij"
     #:email "laszlo@laszlo.is"
     #:user-groups
     '("wheel" "netdev" "audio" "video" "libvirt" "docker")
     #:user-initial-password-hash
     "$6$abc$9a9KlQ2jHee45D./UOzUZWLHjI/atvz2Dp6.Zz6hjRcP2KJv\
G9.lc/f.U9QxNW1.2MZdV1KzW6uMJ0t23KKoN/"


     ;; (crypt "bob" "$6$abc")

     ;; WARNING: This option can reduce the explorability by hiding
     ;; some helpful messages and parts of the interface for the sake
     ;; of minimalistic, less distractive and clean look.  Generally
     ;; it's not recommended to use it.
    #:emacs-advanced-user? #t)

    (feature-gnupg
     #:gpg-primary-key "D36160BF5AC4A0042A135EFE3EED170AF050DEB7"
     #:gpg-ssh-agent? #f)

    (feature-nyxt)

    (feature-waybar
     #:transitions? #t
     #:waybar-modules
           (list
            (waybar-sway-workspaces
             #:persistent-workspaces
             '(("1" . #())))
            (waybar-tray)
            (waybar-idle-inhibitor)
            (waybar-sway-language)
            (waybar-microphone)
            (waybar-volume)
            (waybar-battery #:intense? #f)
            (waybar-clock)))

    (feature-xdg
     #:xdg-user-directories-configuration
     (home-xdg-user-directories-configuration
      (music "$HOME/music")
      (videos "$HOME/videos")
      (pictures "$HOME/pictures")
      (documents "$HOME/documents")
      (download "$HOME/downloads")
      (desktop "$HOME")
      (publicshare "$HOME")
      (templates "$HOME")))

    (feature-emacs-tempel
     #:default-templates? #t
     #:templates
     `(fundamental-mode
       ,#~""
       (t (format-time-string "%Y-%m-%d"))
       ;; TODO: Move to feature-guix
       ;; ,((@ (rde gexp) slurp-file-like)
       ;;   (file-append ((@ (guix packages) package-source)
       ;;                 (@ (gnu packages package-management) guix))
       ;;                "/etc/snippets/tempel/text-mode"))
       ))
    (feature-emacs-time)
    (feature-emacs-git
     #:project-directory "~/work")
    (feature-emacs-org
     #:org-directory "~/work/laszlo/private"
     #:org-indent? #f
     #:org-capture-templates
     ;; https://libreddit.tiekoetter.com/r/orgmode/comments/gc76l3/org_capture_inside_notmuch/
     `(("r" "Reply" entry (file+headline "" "Tasks")
        "* TODO %:subject %?\nSCHEDULED: %t\n%U\n%a\n"
        :immediate-finish t)
       ("t" "Todo" entry (file+headline "" "Tasks") ;; org-default-notes-file
        "* TODO %?\nSCHEDULED: %t\n%a\n")))
    (feature-emacs-org-roam
     ;; TODO: Rewrite to states
     #:org-roam-directory "~/work/laszlo/notes/")
    (feature-emacs-org-agenda
     #:org-agenda-files '("~/work/laszlo/todo.org"))
    (feature-emacs-elfeed
     #:elfeed-org-files '("~/work/laszlo/private/rss.org"))
    (feature-docker)

    (feature-irc-settings
     #:irc-accounts (list
                     (irc-account
                      (id 'srht)
                      (network "chat.sr.ht")
                      (bouncer? #t)
                      (nick "laszlo"))))


    (feature-foot)
    (feature-python)
    ((@ (contrib features emacs-xyz) feature-emacs-evil))
    (feature-keyboard
     ;; To get all available options, layouts and variants run:
     ;; cat `guix build xkeyboard-config`/share/X11/xkb/rules/evdev.lst
     #:keyboard-layout
     (keyboard-layout
      "us,ru"
      #:options '("grp:shifts_toggle" "ctrl:nocaps"))))))
