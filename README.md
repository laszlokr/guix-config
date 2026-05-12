
# Table of Contents

1.  [Laszlo's GNU Guix config](#org397c173)
2.  [Goals](#orgca1f4c6)
3.  [Systems](#orgdecca7b)
    1.  [Hosts](#orgcb0c17a)
    2.  [Remote hosts](#org091af47)


<a id="org397c173"></a>

# Laszlo's GNU Guix config

This repository is for tracking configuration files for personal GNU Guix systems. It is based on [rde](https://git.sr.ht/~abcdw/rde) configuraiton framework and by default depends on Emacs (+evil-collection) and Sway window manager along other Wayland applications.


<a id="orgca1f4c6"></a>

# Goals

To achieve reproducible setup across local devices and personal remote infrastructure (email, website, git, etc.).

The end goal is to have a consistent computing experience and a set of configuretion templates for local and remote hosts, and it is prefereable to have all config files written in Guile Scheme.

The workflow implies having all Emacs buffers in new frames in order to utilize the window management capabilities of Sway instead of Emacs' internal window manager.


<a id="orgdecca7b"></a>

# Systems


<a id="orgcb0c17a"></a>

## Hosts

<table border="2" cellspacing="0" cellpadding="6" rules="groups" frame="hsides">


<colgroup>
<col  class="org-left" />

<col  class="org-left" />

<col  class="org-left" />

<col  class="org-left" />
</colgroup>
<thead>
<tr>
<th scope="col" class="org-left">Host</th>
<th scope="col" class="org-left">Device</th>
<th scope="col" class="org-left">Config</th>
<th scope="col" class="org-left">Description</th>
</tr>
</thead>

<tbody>
<tr>
<td class="org-left">proto</td>
<td class="org-left">Xiaomi 13 laptop</td>
<td class="org-left"><a href="src/laszlo-configs/hosts/proto.scm">proto</a></td>
<td class="org-left">Old laptop for prototyping needs, runs rde</td>
</tr>


<tr>
<td class="org-left">dothome</td>
<td class="org-left">Minisforum Mini PC</td>
<td class="org-left"><a href="src/laszlo-configs/hosts/dothome.scm">dothome</a></td>
<td class="org-left">Main machine for work at home, runs Guix</td>
</tr>


<tr>
<td class="org-left">reform</td>
<td class="org-left">MNT Reform</td>
<td class="org-left">TBD</td>
<td class="org-left">Main laptop, runs Debian + Guix</td>
</tr>


<tr>
<td class="org-left">lawork</td>
<td class="org-left">HP Envy x360</td>
<td class="org-left">TBD</td>
<td class="org-left">Previous main laptop, runs Manjaro + Guix</td>
</tr>
</tbody>
</table>

Currently, there is no reproducibility or consistency among the configuraitons of these hosts. The planned approach is:

1.  Have consistent configs based on rde for `proto` and `dothome` [x]
2.  Customize the configuration
    -   System-wide vim keys [x]
    -   Consistent colorscheme based on palenight [ ]
    -   Emacs as main client for:
        -   Mail (mu4e) [ ]
        -   Telegram (telega) [ ]
        -   Matrix (ement + pantalaimon) [ ]
    -   Find ways to apply:
        -   emacs-frame-only-mode [ ]
        -   SPC as leader key (Doom Emacs style keybdindings) [ ]
        -   UI based on packages made by Nicolas Rougier (NANO Emacs) [ ]
3.  Install the system on MNT Reform (requires custom u-boot and is aarch64) [ ]
4.  Install the system on `lawork` [ ]


<a id="org091af47"></a>

## Remote hosts

The list of remote hosts for laszlo.is domain. The desired setup includes:

1.  Email server [ ]
2.  Personal website [ ]
3.  Matrix and Pantalaimon [ ]
4.  File sync (currently Nextcloud, but can change to Syncthing) [ ]
5.  Wireguard VPN (Currently use [Wirehole](https://github.com/IAmStoxe/wirehole), could try same setup with Guix) [ ]

