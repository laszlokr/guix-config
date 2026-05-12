(use-modules (guix channels))

(list (channel
        (name 'guix)
        (url "https://codeberg.org/guix/guix.git")
        (branch "master")
        (commit
          "03ce76718c41b32d174713c945d269d6fcdd8bf1")
        (introduction
          (make-channel-introduction
            "9edb3f66fd807b096b48283debdcddccfea34bad"
            (openpgp-fingerprint
              "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA"))))
       (channel
        (name 'nonguix)
        (url "https://gitlab.com/nonguix/nonguix")
        (branch "master")
        (commit
          "3df2e2ccc4d6c62e45e7bfc0b49fcf23a2e9ee55")
        (introduction
          (make-channel-introduction
            "897c1a470da759236cc11798f4e0a5f7d4d59fbc"
            (openpgp-fingerprint
              "2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20A0 22FB B2D5"))))
      (channel
        (name 'rde)
        (url "https://git.sr.ht/~abcdw/rde")
        (branch "master")
        (commit
          "079e3e4ee1072b06c2a22485aa0b821019975f19")
        (introduction
          (make-channel-introduction
            "580acbca3e8b6165cdbbb2543b9ce5516b79c5d2"
            (openpgp-fingerprint
              "2841 9AC6 5038 7440 C7E9  2FFA 2208 D209 58C1 DEB0"))))
      (channel
        (name 'small-guix)
        (url "https://codeberg.org/fishinthecalculator/small-guix")
        (branch "master")
        (commit
          "d9e95224b2a80e38455c02df6efd28dc06754766")
        (introduction
          (make-channel-introduction
            "f260da13666cd41ae3202270784e61e062a3999c"
            (openpgp-fingerprint
              "8D10 60B9 6BB8 292E 829B  7249 AED4 1CC1 93B7 01E2")))))
