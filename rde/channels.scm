(use-modules (guix ci)
             (guix channels))

(list
 %default-guix-channel
 (channel
  (name 'nonguix)
  (url "https://gitlab.com/nonguix/nonguix")
  (introduction
   (make-channel-introduction
    "897c1a470da759236cc11798f4e0a5f7d4d59fbc"
    (openpgp-fingerprint
     "2A39 3FFF 68F4 EF7A 3D29  12AF 6F51 20A0 22FB B2D5"))))
 (channel
  (name 'rde)
  (url "https://git.sr.ht/~abcdw/rde")
  (introduction
   (make-channel-introduction
    "b89e78b863c214b74751352e0e659a5e1d6c955d"
    (openpgp-fingerprint
     "2841 9AC6 5038 7440 C7E9  2FFA 2208 D209 58C1 DEB0"))))
 ;; (channel
 ;;  (name 'small-guix)
 ;;  (url "https://codeberg.org/fishinthecalculator/small-guix")
 ;;  (branch "master")
 ;;  (introduction
 ;;    (make-channel-introduction
 ;;      "f260da13666cd41ae3202270784e61e062a3999c"
 ;;      (openpgp-fingerprint
 ;;        "8D10 60B9 6BB8 292E 829B  7249 AED4 1CC1 93B7 01E2"))))
 (channel
  (name 'rosenthal)
  (url "https://github.com/rakino/rosenthal")
  (branch "trunk")
  (introduction
   (make-channel-introduction
    "7677db76330121a901604dfbad19077893865f35"
    (openpgp-fingerprint
     "13E7 6CD6 E649 C28C 3385  4DF5 5E5A A665 6149 17F7"))))
 ;; (channel
 ;;  (name 'repkgd)
 ;;  (url "https://git.sr.ht/~laszlo/repkgd")
 ;;  (introduction
 ;;   (make-channel-introduction
 ;;    "a253d1df3ee6e4505f877cfb92f38bbc503ede4f"
 ;;    (openpgp-fingerprint
 ;;     "D361 60BF 5AC4 A004 2A13 5EFE 3EED 170A F050 DEB7"))))
 ;; (channel
 ;;  (name 'emacs)
 ;;  (url "https://github.com/babariviere/guix-emacs")
 ;;  (introduction
 ;;   (make-channel-introduction
 ;;    "72ca4ef5b572fea10a4589c37264fa35d4564783"
 ;;    (openpgp-fingerprint
 ;;     "261C A284 3452 FB01 F6DF  6CF4 F9B7 864F 2AB4 6F18"))))
 ;; (channel
 ;;  (name 'guix-private)
 ;;  (url "https://git.sr.ht/~laszlo/guix-private")
 ;;  (introduction
 ;;   (make-channel-introduction
 ;;    "d56419a08d7df6dd6fb495ec23ee68a1e7324270"
 ;;    (openpgp-fingerprint
 ;;     "2BA7 5D5E BF89 CD96  0B82 ACEE  86FD E30F 66F0 828A"))))
 )
