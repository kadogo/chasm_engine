(require hyrule.argmove [-> ->>])
(require hyrule.control [unless])

(import os)
(import json)
(import readline)
(import pathlib [Path])
(import hashlib [md5])

;; tomllib for python 3.11 onwards
;; when we move to 3.11, we can remove this
(try
  (import tomllib)
  (except [ModuleNotFoundError]
    (import tomli :as tomllib)))


(setv config-file "config.toml")


;;; -----------------------------------------------------------------------------
;;; config functions
;;; -----------------------------------------------------------------------------

(defn config [#* keys]
  "Get values in a toml file like a hashmap, but default to None."
  (unless (os.path.isfile config-file)
    (raise (FileNotFoundError config-file)))
  (try
    (-> config-file
        (slurp)
        (tomllib.loads)
        (get #* keys))
    (except [KeyError]
      None)))

;;; -----------------------------------------------------------------------------
;;; File & IO functions
;;; -----------------------------------------------------------------------------

(defn rlinput [prompt [prefill ""]]
  "Like python's input() but using readline."
  (readline.set_startup_hook (fn [] (readline.insert_text prefill)))
  (try
    (input prompt)
    (except [EOFError]
      "/quit")
    (finally
      (readline.set_startup_hook))))

(defn load [fname]
  "Read a json file. None if it doesn't exist."
  (let [path (Path fname)]
    (when (path.exists)
      (with [f (open fname
                     :mode "r"
                     :encoding "UTF-8")]
        (json.load f)))))

(defn save [obj fname]
  "Write an object as a json file."
  (with [f (open fname
                 :mode "w"
                 :encoding "UTF-8")]
    (json.dump obj f :indent 4)))

(defn file-append [record fname]
 "Append / write a dict to a file as json.
 If the file does not exist, initialise a file with the record.
 If the file exists, append to it.
 Cobbled together from https://stackoverflow.com/a/31224105
 it overwrites the closing ']' with the new record + a new ']'.
 POSIX expects a trailing newline."
  (when fname
    (if (os.path.isfile fname)
      (with [f (open fname :mode "r+" :encoding "UTF-8")]
        (.seek f 0 os.SEEK_END)
        (.seek f (- (.tell f) 2))
        (.write f (.format ",\n{}]\n" (json.dumps record :indent 4))))
      (with [f (open fname :mode "w" :encoding "UTF-8")]
        (.write f (.format "[\n{}]\n" (json.dumps record :indent 4)))))))

(defn slurp [fname]
  "Read a plain text file."
  (let [path (Path fname)]
    (when (path.exists)
      (path.read-text))))

(defn barf [text fname]
  "Write a plain text file."
  (with [f (open fname :mode "w" :encoding "UTF-8")]
    (.write f text)))

;;; -----------------------------------------------------------------------------
;;; Other utility functions
;;; -----------------------------------------------------------------------------

(defn hash-id [s]
  "Hex digest of md5 hash of string."
  (-> (s.encode "utf-8")
      (md5)
      (.hexdigest)))

(defn short-id [x]
  "First 6 chars of hash-id."
  (cut (hash-id x) 6))

;;; -----------------------------------------------------------------------------
;;; Message and chat functions
;;; -----------------------------------------------------------------------------

;;; -----------------------------------------------------------------------------
;;; String functions
;;; -----------------------------------------------------------------------------
