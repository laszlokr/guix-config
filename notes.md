
# Table of Contents

1.  [Configuring sway and waybar](#org3eac8b4)
2.  [Things to figure out](#org62f260b)
    1.  [Theming](#orgb95ae54)
    2.  [Fonts](#orgc8a10cc)
    3.  [Keybindings](#orge4b2832)
    4.  [Emacs settings](#org5d8675a)
    5.  [How to extend services](#orgf3b984f)
    6.  [How to extend features](#orged8ed5c)

TITLE: rde configuration notes


<a id="org3eac8b4"></a>

# Configuring sway and waybar

Sway configuration was straightforward for keybindings and the new commands were added to `sway-extra-config-service` in [laszlo.scm](src/laszlo-configs/users/laszlo.scm).

The keybinds added:

<table border="2" cellspacing="0" cellpadding="6" rules="groups" frame="hsides">


<colgroup>
<col  class="org-left" />

<col  class="org-left" />
</colgroup>
<thead>
<tr>
<th scope="col" class="org-left">Keys</th>
<th scope="col" class="org-left">Action</th>
</tr>
</thead>

<tbody>
<tr>
<td class="org-left"><code>Super+h</code></td>
<td class="org-left">Focus Left</td>
</tr>


<tr>
<td class="org-left"><code>Super+j</code></td>
<td class="org-left">Focus Down</td>
</tr>


<tr>
<td class="org-left"><code>Super+k</code></td>
<td class="org-left">Focus Up</td>
</tr>


<tr>
<td class="org-left"><code>Super+l</code></td>
<td class="org-left">Focus Right</td>
</tr>


<tr>
<td class="org-left"><code>Super+Ctrl+h</code></td>
<td class="org-left">Move window Left</td>
</tr>


<tr>
<td class="org-left"><code>Super+Ctrl+j</code></td>
<td class="org-left">Move window Down</td>
</tr>


<tr>
<td class="org-left"><code>Super+Ctrl+k</code></td>
<td class="org-left">Move window Up</td>
</tr>


<tr>
<td class="org-left"><code>Super+Ctrl+l</code></td>
<td class="org-left">Move window Right</td>
</tr>


<tr>
<td class="org-left"><code>Super+Shift+o</code></td>
<td class="org-left">Change focus to workspace Left</td>
</tr>


<tr>
<td class="org-left"><code>Super+Shift+p</code></td>
<td class="org-left">Change focus to workspace Right</td>
</tr>


<tr>
<td class="org-left"><code>Super+Ctrl+o</code></td>
<td class="org-left">Move window to workspace Left</td>
</tr>


<tr>
<td class="org-left"><code>Super+Ctrl+p</code></td>
<td class="org-left">Move window to workspace Right</td>
</tr>


<tr>
<td class="org-left"><code>Super+Ctrl+b</code></td>
<td class="org-left">Vertical split</td>
</tr>


<tr>
<td class="org-left"><code>Super+Ctrl+h</code></td>
<td class="org-left">Horizontal split</td>
</tr>


<tr>
<td class="org-left"><code>Super+Ctrl+s</code></td>
<td class="org-left">Stacking layout</td>
</tr>


<tr>
<td class="org-left"><code>Super+Ctrl+w</code></td>
<td class="org-left">Tabbed layout</td>
</tr>


<tr>
<td class="org-left"><code>Super+Ctrl+y</code></td>
<td class="org-left">Toggle split</td>
</tr>


<tr>
<td class="org-left"><code>Super+Ctrl+r</code></td>
<td class="org-left">Resize mode</td>
</tr>


<tr>
<td class="org-left"><code>Super+SPC</code></td>
<td class="org-left">Launcher</td>
</tr>
</tbody>
</table>

Things to improve:

-   Moving windows between workspaces can cause that the workspace becomes empty, and moving the window back will move to a closest workspace which has active windows.

Desired solution:

-   Make workspaces persistent in waybar

Possible ways to achieve:

1.  Add `#:extra-config` parameters to `feature-waybar` in `%laszlo-features` in [laszlo.scm](src/laszlo-configs/users/laszlo.scm)

Looked at definition of `rde features wm` where `waybar-sway-workspaces` is defined and contains `persistent-workspaces` parameter.

    (define* (waybar-sway-workspaces
              #:key
              (bar-id 'main)
              (persistent-workspaces '())
              (all-outputs? #f)
              (format-icons '(("1" . )
                              ("2" . )
                              ("3" . )
                              ("4" . )
                              ("5" . )
                              ("6" . )  ; 
                              ("7" . )  ; 
                              ("8" . )
                              ("9" . )
                              ("10" . )
    
                              ("urgent" . )
                              ("focused" . )
                              ("default" . ))))
      "PERSISTENT-WORKSPACES is a list of pairs workspace and vector of outputs."
      (waybar-module
       'sway/workspaces
       `((disable-scroll . #t)
         (format . {icon})
         ;; FIXME: Height becomes higher when icons are not used.
         (format-icons . ,format-icons)
         (all-outputs . ,all-outputs?)
         (persistent_workspaces . ,persistent-workspaces))
       `(((#{#workspaces}# button)
          ((background . none)
           (border-radius . 0.2em)
           (margin . (0.4em 0.2em))
           (padding . (0.2em 0.2em))
           (color . @base05)))
    
         ((#{#workspaces}# button:hover)
          ((background . none)
           (border-color . @base07)))
    
         ((#{#workspaces}# button.focused)
          ((background . @base02)
           (color . @base07)))
    
         ((#{#workspaces}# button.urgent)
          ((color . @base08))))
       #:placement 'modules-left
       #:bar-id bar-id))

How to define the persistent workspaces in `#:extra-config`

Tried with:

    (feature-waybar
         #:extra-config
         `(waybar-sway-workspaces
           #:persistent-workspaces '(("1" . [])
                                     ("2" . [])
                                     ("3" . [])
                                     ("4" . [])
                                     ("5" . [])
                                     ("6" . [])
                                     ("7" . [])
                                     ("8" . [])
                                     ("9" . [])
                                     ("10" . []))))

Home reconfigure gives error:

    > make dothome/home/reconfigure
    RDE_TARGET=dothome-home ./pre-inst-env target/profiles/guix/bin/guix home \
    reconfigure ./src/laszlo-configs/configs.scm
    guix home: error: failed to load './src/laszlo-configs/configs.scm':
    rde/features.scm:196:10: Wrong type (expecting exact integer): #<&message message: "Duplicate entry came from waybar feature:\n(waybar . #<package waybar@0.9.16 rde/packages/wm.scm:26 7f76c35ecdc0>)\n\nThe previous value was:\n(waybar . #<package waybar@0.9.16 rde/packages/wm.scm:26 7f76c35ecdc0>)\n">
    make: *** [Makefile:53: dothome/home/reconfigure] Error 1
    zsh: exit 2     make dothome/home/reconfigure

Seems like it's not the right way to do it.

Adding a simpler setting

    (feature-waybar
     #:height 20)

It produces the same error as above, will try to figure out the issue and try the second appoach.

After adding waybar to list of features to be removed in order to overwrite settings, home environment was built sucessfully.

    ;; Here we basically remove all the features which has feature name equal
       ;; to either 'base-services or 'kernel.
       (remove (lambda (f) (member (feature-name f) '(base-services
                                                      ssh
                                                      kernel
                                                      fonts
                                                      waybar
                                                      git)))
               %all-features)

Now trying to add `#:persistent-workspaces` parameter to `waybar-sway-workspaces`

    (waybar-sway-workspaces
         #:persistent-workspaces
         `((("1" . [])
            ("2" . [])
            ("3" . [])
            ("4" . [])
            ("5" . [])
            ("6" . [])
            ("7" . [])
            ("8" . [])
            ("9" . [])
            ("10" . []))))

It causes the following error, but at least now getting closer to actually changing some `waybar-sway-workspaces` settings.

    > make dothome/home/reconfigure
    RDE_TARGET=dothome-home ./pre-inst-env target/profiles/guix/bin/guix home \
    reconfigure ./src/laszlo-configs/configs.scm
    guix home: error: failed to load './src/laszlo-configs/configs.scm':
    rde/features.scm:80:0: In procedure %feature-values-procedure:
    In procedure feature-values: Wrong type argument: #<<service> type: #<service-type waybar-module-sway/workspaces 7f45ba381040> value: #<<home-waybar-extension> config: #(((name . main) (modules-left . #(sway/workspaces)) (sway/workspaces (disable-scroll . #t) (format . #{\x7b;icon\x7d;}#) (format-icons ("1" . ) ("2" . ) ("3" . ) ("4" . ) ("5" . ) ("6" . ) ("7" . ) ("8" . ) ("9" . ) ("10" . ) ("urgent" . ) ("focused" . ) ("default" . )) (all-outputs . #f) (persistent_workspaces (("1") ("2") ("3") ("4") ("5") ("6") ("7") ("8") ("9") ("10")))))) style-css: (((#{#workspaces}# button) ((background . none) (border-radius . #{0.2em}#) (margin #{0.4em}# #{0.2em}#) (padding #{0.2em}# #{0.2em}#) (color . @base05))) ((#{#workspaces}# button:hover) ((background . none) (border-color . @base07))) ((#{#workspaces}# button.focused) ((background . @base02) (color . @base07))) ((#{#workspaces}# button.urgent) ((color . @base08)))) %location: #<<location> file: "rde/features/wm.scm" line: 540 column: 3>>>
    make: *** [Makefile:53: dothome/home/reconfigure] Error 1
    zsh: exit 2     make dothome/home/reconfigure

"PERSISTENT-WORKSPACES is a list of pairs workspace and vector of outputs."

For adding persistent workspace settings <https://github.com/Alexays/Waybar/pull/330>

    "sway/workspaces": {
        "persistant_workspaces": {
            "3": [], // Always show a workspace with name '3', on all outputs if it does not exists
            "4": ["eDP-1"], // Always show a workspace with name '4', on output 'eDP-1' if it does not exists
            "5": ["eDP-1", "DP-2"] // Always show a workspace with name '5', on outputs 'eDP-1' and 'DP-2' if it does not exists
        }
    }

1.  Write a `waybar-extra-config-service` in [laszlo.scm](src/laszlo-configs/users/laszlo.scm)


<a id="org62f260b"></a>

# Things to figure out

Tweaking the UX/UI


<a id="orgb95ae54"></a>

## Theming

-   How to set global theme settings (Emacs + Terminals + Bar, etc.)
    -   Global colorscheme set up and switching with Emacs menu or rofi/wofi   <https://github.com/migalmoreno/guix-config/blob/72bd191989e0764d73f526efe88c309fa9a8b697/src/dotfiles/common.scm#L44>
        Currently, calling `C-c t t` toggles dark/light theme only in Emacs, and terminal windows do not change. Bar is grey, so it's not noticable.


<a id="orgc8a10cc"></a>

## Fonts

-   How to set up fonts and sizes
    -   Does it require writing a home service like emacs-extra-packages-service or similar
    -   Where should the feature-fonts be defined, and how to make sure it takes effect on all apps

<https://github.com/migalmoreno/guix-config/blob/72bd191989e0764d73f526efe88c309fa9a8b697/src/dotfiles/common.scm#L603>


<a id="orge4b2832"></a>

## Keybindings

-   How to overwrite sway keybindings defined in rde/src/rde/features/wm.scm

Example: `bindsym --to-code $mod+Shift+l exec $lock` prevents setting this key combination to `bindsym $mod+Shift+l move right` for moving containers around with vim keys instead of arrows.

The same question applies to changing other settings which are defined in rde features. Does it require working on a local fork  of rde to tweak feature source code?


<a id="org5d8675a"></a>

## Emacs settings


<a id="orgf3b984f"></a>

## How to extend services


<a id="orged8ed5c"></a>

## How to extend features

