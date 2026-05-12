(use-modules (guix ci)
             (guix channels))

(list
 (channel
  (name 'guix)
  (url "https://git.savannah.gnu.org/git/guix.git")
  (branch "master")
  (commit "1c4a00820a1ba6265d2d96f4f7804d0807d69dcc")
  (introduction
   (make-channel-introduction
    "9edb3f66fd807b096b48283debdcddccfea34bad"
    (openpgp-fingerprint
     "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA"))))

 (channel
  (name 'nonguix)
  (url "https://gitlab.com/nonguix/nonguix")
  (branch "master")
  (commit "7efff1518917f8bb388454683dc2c2f8e713d642")
  (introduction
   (make-channel-introduction
    "897c1a470da759236cc11798f4e0a5f7d4d59fbc"
    (openpgp-fingerprint
     "2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20A0 22FB B2D5"))))

 (channel
  (name 'mnt-reform-nonguix)
  (url "https://codeberg.org/lykso/mnt-reform-nonguix.git")
  (branch "main")
  (commit "5856db583de085653dccbce042b783d19f72ea97")
  (introduction
   (make-channel-introduction
    "5856db583de085653dccbce042b783d19f72ea97"
    (openpgp-fingerprint
     "5FB0 D57D 6B01 F1B2 76CD AE6B 8381 A360 4C37 F318")))))
