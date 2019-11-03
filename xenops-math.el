(defvar xenops-math-process 'dvisvgm)

(defvar xenops-math-image-margin 20
  "Number of pixels to be used as left margin for non-inline math images")

(defun xenops-math-activate ()
  (define-key xenops-mode-map [(left)] (lambda () (interactive) (xenops-math-toggle-on-transition #'left-char)))
  (define-key xenops-mode-map [(right)] (lambda () (interactive) (xenops-math-toggle-on-transition #'right-char)))
  (define-key xenops-mode-map [(down)] (lambda () (interactive) (xenops-math-toggle-on-transition #'next-line)))
  (define-key xenops-mode-map [(up)] (lambda () (interactive) (xenops-math-toggle-on-transition #'previous-line)))
  (define-key xenops-mode-map [(mouse-1)] #'xenops-math-handle-click)
  (define-key xenops-mode-map [(down-mouse-1)] (lambda () (interactive)))
  ;; TODO: DNW
  (add-to-list 'fill-nobreak-predicate (lambda () (xenops-math-in-inline-math-element-p "\\$"))))

(defun xenops-math-display-image (element)
  (xenops-math-set-org-preview-latex-process-alist! element)
  (let ((beg (plist-get element :begin))
        (end (plist-get element :end)))
    (goto-char beg)
    (unless (eq (get-char-property (point) 'org-overlay-type)
                'org-latex-overlay)
      (let* ((latex (buffer-substring-no-properties beg end))
             (image-type (plist-get (cdr (assq xenops-math-process
                                               org-preview-latex-process-alist))
                                    :image-output-type))
             (margin (if (xenops-math-inline-delimiters-p (plist-get element :delimiters))
                         0
                       `(,xenops-math-image-margin . 0)))
             (cache-file (xenops-math-compute-file-name latex image-type)))
        (unless (file-exists-p cache-file)
          (message "xenops: creating file: %s" cache-file)
          (org-create-formula-image
           latex cache-file org-format-latex-options 'forbuffer xenops-math-process))
        (xenops-math-delete-overlays element)
        (xenops-math-make-overlay beg end cache-file image-type margin)))))

(defun xenops-math-regenerate-image (element)
  (let ((cache-file (xenops-math-get-cache-file element)))
    (when cache-file
      (delete-file cache-file)
      (clear-image-cache cache-file)
      (message "xenops: deleted file: %s" cache-file))
    (xenops-math-delete-overlays element)
    (xenops-math-display-image element)))

(defun xenops-math-hide-image (element)
  (org-remove-latex-fragment-image-overlays (plist-get element :begin)
                                            (plist-get element :end)))

(defun xenops-math-delete-overlays (element)
  (let ((beg (plist-get element :begin))
        (end (plist-get element :end)))
    (dolist (o (overlays-in beg end))
      (when (eq (overlay-get o 'org-overlay-type)
                'org-latex-overlay)
        (delete-overlay o)))))

(defun xenops-math-toggle-on-transition (move-point-command)
  "Display LaTeX on entry to a math element; display image on exit."
  (if (region-active-p)
      (funcall move-point-command)
    (let ((was-in (xenops-math-parse-element-at-point)))
      (funcall move-point-command)
      (save-excursion
        (let ((now-in (xenops-math-parse-element-at-point)))
          (let ((entered (and now-in (not (equal now-in was-in))))
                (exited (and was-in (not (equal was-in now-in)))))
            (cond
             (entered (if (org--list-latex-overlays (plist-get now-in :begin)
                                                    (plist-get now-in :end))
                          (xenops-math-hide-image now-in)))
             (exited (xenops-math-display-image was-in)))))))))

(defun xenops-math-handle-click (event)
  (interactive "e")
  (message "xenops-math-handle-click: %s %s" (event-modifiers event) (memq 'double (event-modifiers event)))
  (cond
   ((memq 'double (event-modifiers event))
    (xenops-math-handle-second-click event))
   (t (xenops-math-handle-first-click event))))

(defun xenops-math-handle-first-click (event)
  (message "xenops-math-handle-first-click")
  (let ((was-in (xenops-math-parse-element-at-point-hack)))
    (mouse-set-point event)
    (save-excursion
      (let ((now-in (xenops-math-parse-element-at-point-hack)))
        (and was-in (not (equal was-in now-in))
             (xenops-math-display-image was-in))))))

(defun xenops-math-handle-second-click (event)
  (message "xenops-math-handle-second-click")
  (-if-let (now-in (xenops-math-parse-element-at-point-hack))
      (xenops-math-hide-image now-in)))

(defun xenops-math-parse-element-at-point-hack ()
  (save-excursion
    ;; TODO: hack: Inline math elements are not
    ;; recognized when point is on match for first
    ;; delimiter
    (forward-char)
    (xenops-math-parse-element-at-point)))

(defun xenops-math-parse-element-at-point ()
  "If point is in previewable block, return plist describing match"
  (let* ((math-delimiters (plist-get (cdr (assoc 'math xenops-ops)) :delimiters))
         (inline-delimiter (car math-delimiters)))
    (assert (xenops-math-inline-delimiters-p inline-delimiter))
    (or (xenops-math-in-inline-math-element-p (car inline-delimiter))
        (-any #'identity (mapcar
                          (lambda (pair)
                            (xenops-math-parse-element-at-point-matching-delimiters
                             (car pair)
                             (cdr pair)
                             (point-min)
                             (point-max)))
                          (cdr math-delimiters))))))

(defun xenops-math-in-inline-math-element-p (delimiter)
  "Is point within an inline block delimited by `delimiter'?"
  (and (oddp (count-matches delimiter (point-at-bol) (point)))
       (xenops-math-parse-element-at-point-matching-delimiters
        delimiter delimiter (point-at-bol) (point-at-eol))))

(defun xenops-math-inline-delimiters-p (delimiters)
  (equal delimiters '("\\$" . "\\$")))

(defun xenops-math-parse-element-at-point-matching-delimiters (start-re end-re lim-up lim-down)
  "If point is between regexps, return plist describing match"
  (let ((element (if (looking-at end-re)
                     ;; This function will return nil if point is between delimiters
                     ;; separated by zero characters.
                     (save-excursion (left-char)
                                     (xenops-math-parse-element-at-point-matching-delimiters-
                                      start-re end-re lim-up lim-down))
                   (xenops-math-parse-element-at-point-matching-delimiters-
                    start-re end-re lim-up lim-down))))
    (when element (plist-put element :delimiters (cons start-re end-re)))))

(defun xenops-math-parse-element-at-point-matching-delimiters- (start-re end-re &optional lim-up lim-down)
  "`org-between-regexps-p' modified to return more match coordinates"
  (save-match-data
    (let ((pos (point))
          (limit-up (or lim-up (save-excursion (outline-previous-heading))))
          (limit-down (or lim-down (save-excursion (outline-next-heading))))
          beg-beg beg-end end-beg end-end)
      (save-excursion
        (and (or (org-in-regexp start-re)
                 (re-search-backward start-re limit-up t))
             (setq beg-beg (match-beginning 0))
             (goto-char (match-end 0))
             (skip-chars-forward " \t\n")
             (setq beg-end (point))
             (re-search-forward end-re limit-down t)
             (> (setq end-end (match-end 0)) pos)
             (goto-char (match-beginning 0))
             (skip-chars-backward " \t\n")
             (setq end-beg (point))
             (not (re-search-backward start-re (1+ beg-beg) t))
             `(:begin ,beg-beg :begin-math ,beg-end :end-math ,end-beg :end ,end-end))))))

(defun xenops-math-set-org-preview-latex-process-alist! (coords)
  (let* ((inline-p (xenops-math-inline-delimiters-p (plist-get coords :delimiters)))
         (bounding-box (if inline-p "1" "10"))
         (dvisvgm-process-plist (cdr (assoc 'dvisvgm org-preview-latex-process-alist)))
         (dvisvgm-image-converter (car (plist-get dvisvgm-process-plist
                                                  :image-converter))))
    ;; TODO: this mutates the global variable!
    (plist-put org-format-latex-options :scale 0.8)
    (assert (and (string-match " -b \\([^ ]+\\) " dvisvgm-image-converter)
                 (plist-put dvisvgm-process-plist
                            :image-converter `(,(replace-match bounding-box t t
                                                               dvisvgm-image-converter 1)))))))

(defun xenops-math-make-overlay (beg end image image-type margin)
  "Copied from org--format-latex-make-overlay"
  (let ((ov (make-overlay beg end))
        (image-type (intern image-type)))
    (overlay-put ov 'org-overlay-type 'org-latex-overlay)
    (overlay-put ov 'evaporate t)
    (overlay-put ov
                 'modification-hooks
                 (list (lambda (o _flag _beg _end &optional _l)
                         (delete-overlay o))))
    (overlay-put ov
                 'display
                 (list 'image :type image-type :file image :ascent 'center :margin margin))))

(defun xenops-math-get-cache-file (element)
  (let* ((beg (plist-get element :begin))
         (end (plist-get element :end))
         (latex (buffer-substring-no-properties beg end))
         (image-type (plist-get (cdr (assq xenops-math-process
                                           org-preview-latex-process-alist))
                                :image-output-type)))
    (xenops-math-compute-file-name latex image-type)))

(defun xenops-math-compute-file-name (latex image-type)
  (let ((hash (sha1 (prin1-to-string
                     (list org-format-latex-header
                           org-latex-default-packages-alist
                           org-latex-packages-alist
                           org-format-latex-options
                           latex)))))
    (format "%s.%s" (f-join (f-expand xenops-cache-directory) hash) image-type)))

(provide 'xenops-math)