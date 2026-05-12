(use-modules (guix channels))

(list (channel
       (name 'guix)
       (url "https://git.savannah.gnu.org/git/guix.git")
       (branch "master")
       (commit "68495de32c232af16321e36a56590c578d4eb629")
       (introduction
        (make-channel-introduction
         "9edb3f66fd807b096b48283debdcddccfea34bad"
         (openpgp-fingerprint
          "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA"))))
      (channel
       (name 'nonguix)
       (url "https://gitlab.com/nonguix/nonguix")
       (branch "master")
       (commit "5f2630e69fbbe9e79c350a67545f0fef7e93e223")
       (introduction
        (make-channel-introduction
         "897c1a470da759236cc11798f4e0a5f7d4d59fbc"
         (openpgp-fingerprint
          "2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20A0 22FB B2D5"))))
      (channel
       (name 'rde)
       (url "https://git.sr.ht/~abcdw/rde")
       (branch "master")
       (commit "458b82e128bd98a19e995e72377161f2cfd964a9")
       (introduction
        (make-channel-introduction
         "b89e78b863c214b74751352e0e659a5e1d6c955d"
         (openpgp-fingerprint
          "2841 9AC6 5038 7440 C7E9  2FFA 2208 D209 58C1 DEB0"))))
      (channel
       (name 'rosenthal)
       (url "https://github.com/rakino/rosenthal")
       (branch "trunk")
       (commit "9e60a11917cbdca57e10c51e174dfa56379e74cc")
       (introduction
        (make-channel-introduction
         "7677db76330121a901604dfbad19077893865f35"
         (openpgp-fingerprint
          "13E7 6CD6 E649 C28C 3385  4DF5 5E5A A665 6149 17F7")))))
