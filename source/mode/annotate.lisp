;;;; SPDX-FileCopyrightText: Atlas Engineer LLC
;;;; SPDX-License-Identifier: BSD-3-Clause

(nyxt:define-package :nyxt/annotate-mode
  (:documentation "Mode to annotate documents.
Annotations are persisted to disk."))
(in-package :nyxt/annotate-mode)

(define-mode annotate-mode ()
  "Annotate document with arbitrary comments.
Annotations are persisted to disk, see the `annotations-file' mode slot."
  ((visible-in-status-p nil)
   (annotations-file
    (make-instance 'annotations-file)
    :type annotations-file
    :documentation "File where annotations are saved.")))

(defmethod annotations-file ((buffer buffer))
  (annotations-file (find-submode 'annotate-mode buffer)))

(define-class annotations-file (files:data-file nyxt-lisp-file)
  ((files:base-path #p"annotations")
   (files:name "annotations"))
  (:export-class-name-p t)
  (:accessor-name-transformer (class*:make-name-transformer name)))

(define-class annotation ()
  ((data
    ""
    :export nil
    :documentation "The annotation data.")
   (tags
    '()
    :type (list-of string))
   (date (local-time:now)))
  (:export-class-name-p t)
  (:export-accessor-names-p t)
  (:accessor-name-transformer (class*:make-name-transformer name)))

(define-class url-annotation (annotation)
  ((url nil)
   (page-title ""))
  (:export-class-name-p t)
  (:export-accessor-names-p t)
  (:accessor-name-transformer (class*:make-name-transformer name)))

(define-class snippet-annotation (url-annotation)
  ((snippet nil :documentation "The snippet of text being annotated."))
  (:export-class-name-p t)
  (:export-accessor-names-p t)
  (:accessor-name-transformer (class*:make-name-transformer name)))

;; TODO: Wrap in <div>s with special CSS classes.
(defmethod render ((annotation url-annotation))
  (spinneret:with-html-string
    (:dl
     (:dt "URL")
     (:dd (render-url (url annotation)))
     (:dt "Title")
     (:dd (snippet annotation))
     (:dt "Tags")
     (:dd (format nil "~{~a ~}" (tags annotation))))
    (:p (data annotation))))

(defmethod render ((annotation snippet-annotation))
  (spinneret:with-html-string
    (:dl
     (:dt "URL")
     (:dd (render-url (url annotation)))
     (:dt "Title")
     (:dd (page-title annotation))
     (:dt "Snippet")
     (:dd (snippet annotation))
     (:dt "Tags")
     (:dd (format nil "~{~a ~}" (tags annotation))))
    (:p (data annotation))))

(defun annotation-add (annotation)
  (files:with-file-content (annotations (annotations-file (current-buffer)))
    (push annotation annotations)))

(defun annotations ()
  (files:content (annotations-file (current-buffer))))

(define-command annotate-current-url
    (&key (buffer (current-buffer))
     (data (prompt1 :prompt "Annotation"
                    :sources (make-instance 'prompter:raw-source
                                            :name "Note")))
     (tags (prompt
            :prompt "Tag(s)"
            :sources (list (make-instance 'prompter:word-source
                                          :name "New tags"
                                          :multi-selection-p t)
                           (make-instance 'keyword-source :buffer buffer)
                           (make-instance 'annotation-tag-source)))))
  "Create an annotation of the URL of BUFFER.

DATA and TAGS are passed as arguments to `url-annotation' make-instance."
  (annotation-add (make-instance 'url-annotation
                                 :url (url buffer)
                                 :data data
                                 :page-title (title buffer)
                                 :tags tags)))

(define-command annotate-highlighted-text
    (&key (buffer (current-buffer))
     (snippet (ffi-buffer-copy buffer))
     (data (prompt1 :prompt "Annotation"
                    :sources (make-instance 'prompter:raw-source
                                            :name "Note")))
     (tags (prompt
            :prompt "Tag(s)"
            :sources (list (make-instance 'prompter:word-source
                                          :name "New tags"
                                          :multi-selection-p t)
                           (make-instance 'keyword-source :buffer buffer)
                           (make-instance 'annotation-tag-source)))))
  "Create an annotation for the highlighted text of BUFFER.

DATA, SNIPPET, and TAGS are passed as arguments to `snippet-annotation'
make-instance."
  (annotation-add (make-instance 'snippet-annotation
                                 :snippet snippet
                                 :url (url buffer)
                                 :page-title (title buffer)
                                 :data data
                                 :tags tags)))

(defun render-annotations (annotations)
  "Show the ANNOTATIONS in a new buffer"
  (spinneret:with-html-string
    (:h1 "Annotations")
    (loop for annotation in annotations
          collect (:div (:raw (render annotation))
                        (:hr)))))

(define-internal-page-command-global show-annotations-for-current-url
    (&key (source-buffer (current-buffer)))
    (buffer "*Annotations*")
  "Create a new buffer with the annotations of the current URL of BUFFER."
  (let ((annotations (files:content (annotations-file buffer))))
    (let ((filtered-annotations (sera:filter (alex:curry #'url-equal (url source-buffer))
                                             annotations :key #'url)))
      (render-annotations filtered-annotations))))

(define-class annotation-source (prompter:source)
  ((prompter:name "Annotations")
   (prompter:constructor (files:content (annotations-file (current-buffer))))
   (prompter:multi-selection-p t)))

(define-class annotation-tag-source (prompter:source)
  ((prompter:name "Tags")
   (prompter:filter-preprocessor
    (lambda (initial-suggestions-copy source input)
      (prompter:delete-inexact-matches
       initial-suggestions-copy
       source
       (last-word input))))
   (prompter:filter
    (lambda (suggestion source input)
      (prompter:fuzzy-match suggestion source (last-word input))))
   (prompter:multi-selection-p t)
   (prompter:constructor
    (let ((annotations (files:content (annotations-file (current-buffer)))))
      (sort (remove-duplicates
             (reduce/append (mapcar #'tags annotations))
             :test #'string-equal)
            #'string-lessp))))
  (:accessor-name-transformer (class*:make-name-transformer name)))

(define-internal-page-command-global show-annotation ()
    (buffer "*Annotations*")
  "Show an annotation(s)."
  (let ((selected-annotations
          (prompt
           :prompt "Show annotation(s)"
           :sources (make-instance 'annotation-source
                                   :return-actions nil))))
    (render-annotations selected-annotations)))

(define-internal-page-command-global show-annotations ()
    (buffer "*Annotations*")
  "Show all annotations"
  (render-annotations (files:content (annotations-file buffer))))
