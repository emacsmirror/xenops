(ert-deftest xenops-math-parse-element-from-string ()
  (should (equal (xenops-math-parse-element-from-string "$x$")
                 '(:begin 1 :begin-math 2 :end-math 3 :end 4 :type math
                          :delimiters ("\\$" . "\\$"))))
  (should (equal (xenops-math-parse-element-from-string
                  (s-trim
                   "
\\begin{align*}
  x
\\end{align*}
"))
                 '(:begin 1 :begin-math 18 :end-math 19 :end 32 :type math
                          :delimiters ("^[ \t]*\\\\begin{align\\*?}" .
                                       "^[ \t]*\\\\end{align\\*?}")))))

(ert-deftest xenops-math-parse-match ())

(ert-deftest xenops-math-parse-element-at-point ())

(ert-deftest xenops-math-in-inline-math-element-p ())

(ert-deftest xenops-math-parse-element-at-point-matching-delimiters ())