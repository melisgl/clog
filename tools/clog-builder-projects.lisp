(in-package :clog-tools)

(defun projects-setup (panel)
  (let* ((app (connection-data-item panel "builder-app-data")))
    (when (uiop:directory-exists-p #P"~/common-lisp/")
      (pushnew #P"~/common-lisp/" ql:*local-project-directories*))
    (add-select-option (project-list panel) "None" "None")
    (dolist (n (sort (ql:list-local-systems) #'string-lessp))
      (add-select-option (project-list panel) n n))
    (cond((current-project app)
          (setf (text-value (project-list panel)) (current-project app))
          (projects-populate panel))
         (t
          (setf (text-value (project-list panel)) "None")))))

(defun projects-run (panel)
  (let ((val (text-value (entry-point panel))))
    (unless (equal val "")
      (let ((result (capture-eval (format nil "(~A)" val) :clog-obj panel
                                      :eval-in-package "clog-user")))
        (clog-web-alert (connection-body panel) "Result"
                        (format nil "~&result: ~A" result)
                        :color-class "w3-green"
                        :time-out 3)))))

(defun projects-entry-point-change (panel)
  (let* ((sys         (text-value (project-list panel)))
         (entry-point (text-value (entry-point panel)))
         (fname       (asdf:system-source-file (asdf:find-system sys)))
         (sys-list    '()))
    (with-open-file (s fname)
      (loop
        (let* ((line (read s nil)))
          (unless line (return))
          (when (equalp (format nil "~A" (second line)) sys)
            (if (getf line :entry-point)
                (setf (getf line :entry-point) entry-point)
                (setf line (append line `(:entry-point ,entry-point)))))
          (push line sys-list))))
    (with-open-file (s fname :direction :output :if-exists :rename)
      (let ((*print-case* :downcase))
        (dolist (n (reverse sys-list))
          (pprint n s))))))

(defun projects-rerender (panel)
  (let* ((app (connection-data-item panel "builder-app-data"))
         (sel (text-value (project-list panel)))
         (sys (asdf:find-system (format nil "~A/tools" sel))))
    (dolist (n (asdf:module-components sys))
      (let ((name      (format nil "~A" (asdf:component-relative-pathname n)))
            (file-name (asdf:component-pathname n)))
        (when (and (> (length name) 5)
                   (equal (subseq name (- (length name) 5)) ".clog"))
          (let* ((win              (create-gui-window panel :top 40 :left 225
                                                            :width 645 :height 430))
                 (box              (create-panel-box-layout (window-content win)
                                                            :left-width 0 :right-width 0
                                                            :top-height 33 :bottom-height 0))
                 (content          (center-panel box))
                 (panel-id         (html-id content))
                 (render-file-name (format nil "~A~A.lisp"
                                           (directory-namestring file-name)
                                           (pathname-name file-name))))
            (setf-next-id content 1)
            (setf (overflow content) :auto)
            (init-control-list app panel-id)
            (clrhash (get-control-list app panel-id))
            ;; preset in case of empty clog file
            (setf (attribute content "data-clog-name") "empty-clog-file")
            (setf (attribute content "data-clog-type") "clog-data")
            (setf (attribute content "data-in-package") "clog-user")
            (setf (attribute content "data-custom-slots") "")
            (setf (inner-html content)
                  (or (read-file file-name)
                      ""))
            (on-populate-loaded-window content :win win)
            (setf (window-title win) (attribute content "data-clog-name"))
            (write-file (render-clog-code content (bottom-panel box))
                        render-file-name)
            (window-close win)
            (format t "~A -> ~A~%" file-name render-file-name)))))))

(defun projects-populate (panel)
  (let ((app (connection-data-item panel "builder-app-data"))
        (already (asdf/operate:already-loaded-systems))
        (sel (text-value (project-list panel))))
    (reset-control-pallete panel)
    (setf (inner-html (runtime-list panel)) "")
    (setf (inner-html (designtime-list panel)) "")
    (setf (inner-html (runtime-deps panel)) "")
    (setf (inner-html (design-deps panel)) "")
    (setf (text-value (entry-point panel)) "")
    (setf (disabledp (runtime-add-lisp panel)) t)
    (setf (disabledp (runtime-delete panel)) t)
    (setf (disabledp (designtime-add-lisp panel)) t)
    (setf (disabledp (designtime-add-clog panel)) t)
    (setf (disabledp (designtime-delete panel)) t)
    (setf (disabledp (runtime-add-dep panel)) t)
    (setf (disabledp (runtime-del-dep panel)) t)
    (setf (disabledp (design-add-dep panel)) t)
    (setf (disabledp (design-del-dep panel)) t)
    (setf (disabledp (design-plugin panel)) t)
    (setf (disabledp (entry-point panel)) t)
    (setf (disabledp (run-button panel)) t)
    (setf (current-project app) (if (equal sel "None")
                                    nil
                                    sel))
    (when (current-project app)
      (cond ((member sel already :test #'equal)
             ;; entry point
             (setf (text-value (entry-point panel))
                   (or (asdf/system:component-entry-point
                        (asdf:find-system sel))
                       ""))
             (setf (current-project-dir app)
                   (asdf:component-pathname
                    (asdf:find-system sel)))
             ;; fill runtime
             (dolist (n (asdf:module-components
                         (asdf:find-system sel)))
               (let ((name (asdf:component-relative-pathname n))
                     (path (asdf:component-pathname n)))
                 (add-select-option (runtime-list panel) path name)))
             (dolist (n (asdf:system-depends-on
                         (asdf:find-system sel)))
               (add-select-option (runtime-deps panel) n n))
             ;; fill designtime)
             (handler-case
                 (let ((sys (asdf:find-system (format nil "~A/tools" sel))))
                   (dolist (n (asdf:module-components sys))
                     (let ((name (asdf:component-relative-pathname n))
                           (path (asdf:component-pathname n)))
                       (add-select-option (designtime-list panel) path name)))
                   (dolist (n (asdf:system-depends-on
                               (asdf:find-system sys)))
                     (add-select-option (design-deps panel) n n))
                   (cond ((member "clog" (asdf:system-defsystem-depends-on sys) :test #'equal)
                          (setf (disabledp (runtime-add-lisp panel)) nil)
                          (setf (disabledp (runtime-delete panel)) nil)
                          (setf (disabledp (designtime-add-lisp panel)) nil)
                          (setf (disabledp (designtime-add-clog panel)) nil)
                          (setf (disabledp (designtime-delete panel)) nil)
                          (setf (disabledp (runtime-add-dep panel)) nil)
                          (setf (disabledp (runtime-del-dep panel)) nil)
                          (setf (disabledp (design-add-dep panel)) nil)
                          (setf (disabledp (design-del-dep panel)) nil)
                          (setf (disabledp (design-plugin panel)) nil)
                          (setf (disabledp (entry-point panel)) nil)
                          (setf (disabledp (run-button panel)) nil))
                         (t
                          (alert-toast panel "Warning" "Missing :defsystem-depends-on (:clog)"
                                       :color-class "w3-yellow" :time-out 2))))
               (t (c)
                 (declare (ignore c))
                 (add-select-option (designtime-list panel) "" "Missing /tools")
                 (add-select-option (design-deps panel) "" "Missing /tools"))))
            (t
             (confirm-dialog panel "Load project?"
                             (lambda (answer)
                               (cond (answer
                                      (ql:quickload sel)
                                      (ignore-errors
                                       (ql:quickload (format nil "~A/tools" sel)))
                                      (ql:quickload sel)
                                      (projects-populate panel))
                                     (t
                                      (setf (current-project app) nil)
                                      (setf (text-value (project-list panel)) "None"))))
                             :title "System not loaded"))))))

(defun projects-add-dep (panel sys)
  (Input-dialog panel "Enter system name:"
                (lambda (result)
                  (when result
                    (add-dep-to-defsystem sys result)
                    (ql:quickload sys)
                    (projects-populate panel)))
                :height 230)
  (ql:quickload sys))

(defun projects-add-plugin (panel sys)
  (input-dialog panel (format nil "Enter plugin name (without /tools), ~
                       plugin will be added to the runtime and designtime:")
                (lambda (result)
                  (when result
                    (let* ((s (format nil "~A/tools" sys)))
                      (add-dep-to-defsystem s (format nil "~A/tools" result))
                      (ql:quickload s))
                    (add-dep-to-defsystem sys result)
                    (ql:quickload sys)
                    (projects-populate panel)))
                :height 250))

(defun add-dep-to-defsystem (sys file)
  (let ((fname    (asdf:system-source-file (asdf:find-system sys)))
        (sys-list '()))
    (with-open-file (s fname)
      (loop
        (let* ((line (read s nil)))
          (unless line (return))
          (when (equalp (format nil "~A" (second line)) sys)
            (setf (getf line :depends-on)
                  (append (getf line :depends-on) `(,file))))
          (push line sys-list))))
    (with-open-file (s fname :direction :output :if-exists :rename)
      (let ((*print-case* :downcase))
        (dolist (n (reverse sys-list))
          (pprint n s))))))

(defun remove-dep-from-defsystem (sys file)
  (let ((fname    (asdf:system-source-file (asdf:find-system sys)))
        (sys-list '()))
    (with-open-file (s fname)
      (loop
        (let* ((line (read s nil)))
          (unless line (return))
          (when (equalp (format nil "~A" (second line)) sys)
            (let (new-comp)
              (dolist (n (getf line :depends-on))
                (unless (equalp (format nil "~A" n) file)
                  (push n new-comp)))
              (setf (getf line :depends-on) (reverse new-comp))))
          (push line sys-list))))
    (with-open-file (s fname :direction :output :if-exists :rename)
      (let ((*print-case* :downcase))
        (dolist (n (reverse sys-list))
          (pprint n s))))))

(defun projects-add-lisp (panel sys)
  (Input-dialog panel "Enter lisp component name (with out .lisp):"
                (lambda (result)
                  (when result
                    (let ((path (asdf:component-pathname
                                 (asdf:find-system sys))))
                      (write-file "" (format nil "~A~A.lisp"
                                             path result)
                                  :action-if-exists nil)
                      (add-file-to-defsystem sys result :file)
                      (ql:quickload sys)
                      (projects-populate panel))))
                :height 230)
  (ql:quickload sys))

(defun projects-add-clog (panel sys)
  (input-dialog panel (format nil "Enter clog component name (with out .clog), ~
                       a lisp component will also be created in the runtime system:")
                (lambda (result)
                  (when result
                    (let* ((s (format nil "~A/tools" sys))
                           (path (asdf:component-pathname
                                  (asdf:find-system s))))
                      (write-file "" (format nil "~A~A.clog"
                                             path result)
                                  :action-if-exists nil)
                      (add-file-to-defsystem s result :clog-file)
                      (ql:quickload s))
                    (let ((path (asdf:component-pathname
                                 (asdf:find-system sys))))
                      (write-file "" (format nil "~A~A.lisp"
                                             path result)
                                  :action-if-exists nil)
                      (add-file-to-defsystem sys result :file)
                      (ql:quickload sys)
                      (projects-populate panel))))
                :height 250))

(defun add-file-to-defsystem (system file ftype)
  (let ((fname    (asdf:system-source-file (asdf:find-system system)))
        (sys-list '()))
    (with-open-file (s fname)
      (loop
        (let* ((line (read s nil)))
          (unless line (return))
          (when (equalp (format nil "~A" (second line)) system)
            (setf (getf line :components)
                  (append (getf line :components) `((,ftype ,file)))))
          (push line sys-list))))
    (with-open-file (s fname :direction :output :if-exists :rename)
      (let ((*print-case* :downcase))
        (dolist (n (reverse sys-list))
          (pprint n s))))))

(defun remove-file-from-defsystem (system file ftype)
  (let ((fname    (asdf:system-source-file (asdf:find-system system)))
        (sys-list '()))
    (with-open-file (s fname)
      (loop
        (let* ((line (read s nil)))
          (unless line (return))
          (when (equalp (format nil "~A" (second line)) system)
            (let (new-comp)
              (dolist (n (getf line :components))
                (unless (and (equal (first n) ftype)
                             (equalp (second n) file))
                  (push n new-comp)))
              (setf (getf line :components) (reverse new-comp))))
          (push line sys-list))))
    (with-open-file (s fname :direction :output :if-exists :rename)
      (let ((*print-case* :downcase))
        (dolist (n (reverse sys-list))
          (pprint n s)))))
  (ql:quickload system))

(defun open-projects-component (target system list)
  (let ((disp (select-text target))
        (item (text-value target)))
    (cond ((equal item "")
           (alert-toast target "Invalid action" "No /tools project" :time-out 1))
          ((equal (subseq item (1- (length item))) "/")
           (setf (inner-html list) "")
           (dolist (n (asdf:module-components
                       (asdf:find-component
                        (asdf:find-system system)
                        (subseq disp 0 (1- (length disp))))))
             (let ((name (asdf:component-relative-pathname n))
                   (path (asdf:component-pathname n)))
               (add-select-option list path name))))
          ((and (> (length item) 5)
                (equal (subseq item (- (length item) 5)) ".clog"))
           (on-new-builder-panel target :open-file item))
          (t
           (on-open-file target :open-file item)))))