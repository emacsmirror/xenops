;; -*- lexical-binding: t -*-

(setq xenops-test--example-svg
      "<?xml version='1.0' encoding='UTF-8'?>
<!-- This file was generated by dvisvgm 2.3.5 -->
<svg height='1.992528pt' version='1.1' viewBox='-0.996264 -0.996264 1.992528 1.992528' width='1.992528pt' xmlns='http://www.w3.org/2000/svg' xmlns:xlink='http://www.w3.org/1999/xlink'>
<g id='page1' transform='matrix(1.253143 0 0 1.253143 0 0)'>
<rect fill='#ffffff' height='0' width='0' x='0' y='0'/>
</g>
</svg>")

(setq xenops-test--example-svg--cache-file (make-temp-file "xenops-test" nil ".tex"))

(defun xenops-test--mock-xenops-math-latex-create-image (element _ _ _ file callback)
  (with-temp-buffer
    (insert xenops-test--example-svg)
    (write-file file))
  (funcall callback element))

(defun xenops-test--mock-xenops-math-render (element &optional _)
  "A mock of `xenops-math-render'."
  (xenops-test--mock-xenops-math-latex-create-image element nil nil nil
                                                    xenops-test--example-svg--cache-file #'identity)
  (xenops-math-display-image element nil nil xenops-test--example-svg--cache-file "svg"))

(defmacro xenops-test--with-xenops-render (buffer-contents &rest body)
  `(cl-letf (((symbol-function 'xenops-math-latex-create-image)
              #'xenops-test--mock-xenops-math-latex-create-image))
     (let ((xenops-cache-directory (make-temp-file "xenops-test-" 'dir))
           ;; We are relying on this file being treated as its own master file by
           ;; `TeX-region-create'. If the file name does not end in .tex, then a master file will be
           ;; sought with the .tex suffix, and this will fail.
           (file (make-temp-file "xenops-test-" nil ".tex"))
           (before "\\documentclass{article}\n\\begin{document}\n")
           (after "\n\\end{document}"))
       (with-temp-buffer
         (insert (concat before ,buffer-contents after))
         (write-file file)
         (LaTeX-mode)
         (xenops-mode)
         (mark-whole-buffer)
         (xenops-render)
         (goto-char (length before))
         ,@body))))


(defun xenops-test--do-apply-parse-next-element-test (input-text &rest expected-properties)
  (with-temp-buffer
    (save-excursion (insert input-text))
    (let ((element (xenops-apply-parse-next-element)))
      (cl-loop for (k v) in (-partition 2 expected-properties)
               do (should (equal (plist-get element k) v))))))
