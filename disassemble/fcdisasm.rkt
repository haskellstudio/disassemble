#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; fcdisasm - The Full-Color Disassembler
;; Copyright © 2008, 2009, 2010, 2011 Göran Weinholt <goran@weinholt.se>

;; Permission is hereby granted, free of charge, to any person obtaining a
;; copy of this software and associated documentation files (the "Software"),
;; to deal in the Software without restriction, including without limitation
;; the rights to use, copy, modify, merge, publish, distribute, sublicense,
;; and/or sell copies of the Software, and to permit persons to whom the
;; Software is furnished to do so, subject to the following conditions:

;; The above copyright notice and this permission notice shall be included in
;; all copies or substantial portions of the Software.

;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
;; THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
;; FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
;; DEALINGS IN THE SOFTWARE.
#lang racket

;; This program is an example of how to use (industria disassembler
;; x86) and a novelty: first disassembler to go *full color* for the
;; hex dump!

(require rnrs
         (only-in srfi/1 list-index)
         (prefix-in x86: disassemble/x86)
         (only-in disassemble/x86 invalid-opcode?))

(provide disassemble)

(define archs
  (list (cons "x86-16" (lambda (p c) (x86:get-instruction p 16 c)))
        (cons "x86-32" (lambda (p c) (x86:get-instruction p 32 c)))
        (cons "x86-64" (lambda (p c) (x86:get-instruction p 64 c)))))

;; Print an instruction with hexadecimal numbers.
(define (print-instr/sexpr i)
  (cond ((pair? i)
         (display "(")
         (let lp ((i i))
           (unless (null? i)
             (print-instr/sexpr (car i))
             (unless (null? (cdr i))
               (display #\space)
               (lp (cdr i)))))
         (display ")"))
        ((number? i)
         (display "#x")
         (display (number->string i 16)))
        (else
         (display i))))

(define (disassemble p get-instruction color end-position pc symbols)
  (define (display-addr addr)
    (let ((x (number->string addr 16)))
      (if (< (string-length x) 8)
          (display (make-string (- 8 (string-length x)) #\space)))
      (display x)))
  (define (next-symbol symbols pc)
    (cond ((null? symbols) symbols)
          ((null? (cdr symbols)) symbols)
          ((or (> pc (cadar symbols))
               (= pc (caadr symbols)))
           (next-symbol (cdr symbols) pc))
          
          (else symbols)))
  (let lp ((pos (port-position p))
           (pc pc)
           (symbols (next-symbol symbols pc)))
    (let* ((tagged-bytes '())
           (i (guard (con
                      ((invalid-opcode? con)
                       (list 'bad:
                             (condition-message con))))
                (get-instruction p
                                 (lambda x
                                   (set! tagged-bytes (cons x tagged-bytes))))))
           (new-pos (port-position p)))
      ;; Print info from the symbol table
      (unless (null? symbols)
        (when (= pc (caar symbols))
          (let ((sym (car symbols)))
            (newline)
            (when color (display "\x1b;[4m"))
            (display (number->string (car sym) 16))
            (display #\-)
            (display (number->string (cadr sym) 16))
            (when color (display "\x1b;[0m"))
            (display #\space)
            (display (caddr sym))
            (newline))))
      ;; Print instructions
      (unless (or (eof-object? i)
                  (and end-position (> new-pos end-position)))
        (display-addr pc)
        (display ": ")
        (for-each (lambda (x)
                    (let ((tag (car x))
                          (bytes (cdr x)))
                      (cond ((eq? tag '/is4)
                             (when color
                               (display "\x1b;[1;34m"))
                             (display (number->string (bitwise-bit-field (car bytes) 4 8) 16))
                             (when color
                               (display "\x1b;[1;37m"))
                             (display (number->string (bitwise-bit-field (car bytes) 0 4) 16)))
                            (else
                             (when color
                               (case tag
                                 ((modr/m sib tfr/exg/sex) (display "\x1b;[1;34m"))
                                 ((opcode) (display "\x1b;[1;32m"))
                                 ((prefix) (display "\x1b;[1;33m"))
                                 ((immediate) (display "\x1b;[1;37m"))
                                 ((disp offset) (display "\x1b;[1;35m"))
                                 (else (display "\x1b;[0m"))))
                             (for-each (lambda (byte)
                                         (when (< byte #x10)
                                           (display #\0))
                                         (display (number->string byte 16)))
                                       bytes)))))
                  (reverse tagged-bytes))
        (when color
          (display "\x1b;[0m"))
        (display (make-string (- 31 (* 2 (- new-pos pos))) #\space))
        (print-instr/sexpr i)
        (newline)
        (let ((new-pc (+ pc (- new-pos pos))))
          (lp new-pos new-pc (next-symbol symbols new-pc)))))))

#;
(define (get-elf-disassembler machine endianness)
  (cond #;((= machine EM-ARM) (lambda (p c) (arm:get-instruction p #f c)))
        ((= machine EM-386) (lambda (p c) (x86:get-instruction p 32 c)))
        ((= machine EM-X86-64) (lambda (p c) (x86:get-instruction p 64 c)))
        ((= machine EM-68HC12) (lambda (p c) (m68hc12:get-instruction p c)))
        ((= machine EM-MIPS) (lambda (p c) (mips:get-instruction p endianness c)))
        (else
         (display "No support for this architecture: ")
         (cond ((assv machine elf-machine-names) =>
                (lambda (n) (display (cdr n))))
               (else
                (display "Unknown architecture (")
                (display machine)
                (display ")")))
         (newline)
         (exit))))
#;
;; Returns a list of (start-addr end-addr symbol) in increasing order.
(define (parse-elf-symbols image)
  (cond ((elf-image-symbols image) =>
         (lambda (symbols)
           (vector-sort! (lambda (s1 s2)
                           (> (elf-symbol-value (cdr s1))
                              (elf-symbol-value (cdr s2))))
                         symbols)
           (let lp ((ret '())
                    (i 0))
             (if (= i (vector-length symbols))
                 ret
                 (let* ((sym (vector-ref symbols i))
                        (name (car sym)) (s (cdr sym)))
                   (if (or (eqv? (elf-symbol-name s) 0)
                           (eqv? (elf-symbol-shndx s) SHN-UNDEF))
                       (lp ret (+ i 1))
                       (lp (cons (list (elf-symbol-value s)
                                       (+ (elf-symbol-value s)
                                          (elf-symbol-size s))
                                       name)
                                 ret)
                           (+ i 1))))))))
        (else '())))

(define (disassemble-file filename arch color)
  (cond #;((is-elf-image? filename)
         (display "ELF image detected. Looking for .text section...\n")
         (let* ((image (open-elf-image filename))
                (text (elf-image-section-by-name image ".text")))
           (cond ((and text (= (elf-section-type text) SHT-PROGBITS))
                  (let ((get-instruction (get-elf-disassembler
                                          (elf-image-machine image)
                                          (if (= (elf-image-endianness image) 1)
                                              (endianness little) (endianness big))))
                        (symbols (parse-elf-symbols image)))
                    (set-port-position! (elf-image-port image)
                                        (elf-section-offset text))
                    (disassemble (elf-image-port image)
                                 get-instruction color
                                 (+ (elf-section-offset text)
                                    (elf-section-size text))
                                 (elf-section-addr text)
                                 symbols)))
                 (else
                  (display "This ELF image has no .text section with executable code.\n")
                  (display "No disassembly for you.\n")))))
        (else
         (disassemble (open-file-input-port filename)
                      (cdr (assoc arch archs))
                      color #f 0 '()))))

(define (parse-args args)
  (define (help . msg)
    (let ((x (current-error-port)))
      (when msg (display (car msg) x) (newline x) (newline x))
      (display "fcdisasm - Full-color disassembler

Usage: fcdisasm [-b|--bits <bits>] [-a|--arch <arch>] [--nocolor] [--] <filename>

The <bits> argument can be either 16 (default), 32 or 64 This is
shorthand for --arch x86-16 etc.

The <arch> is one of x86-16, x86-32, x86-64, hc12, mipsel, mipsbe,
8080. It is used for non-ELF files.

The --nocolor flag suppresses the color output.

The colors used are:
 * Blue for ModR/M and SIB bytes
 * Green for opcode bytes
 * Yellow for prefix bytes
 * White for immediates
 * Magenta for offsets.

Author: Göran Weinholt <goran@weinholt.se>.
" x)
      (exit 1)))
  (let lp ((filename #f)
           (color #t)
           (arch "x86-16")
           (args args))
    (cond ((null? args)
           (unless filename
             (help "ERROR: No filename given."))
           (values filename arch color))
          ((or (string=? (car args) "--bits")
               (string=? (car args) "-b"))
           (if (null? (cdr args)) (help "ERROR: -b needs an argument (16, 32, 64)"))
           (cond ((assoc (cadr args) '(("64" . "x86-64") ("32" . "x86-32") ("16" . "x86-16"))) =>
                  (lambda (x)
                    (lp filename color (cdr x) (cddr args))))
                 (else
                  (help "ERROR: invalid argument for --bits flag"))))
          ((member (car args) '("-a" "--arch"))
           (if (null? (cdr args)) (help "ERROR: -a needs an argument"))
           (cond ((assoc (cadr args) archs) =>
                  (lambda (_)
                    (lp filename color (cadr args) (cddr args))))
                 (else
                  (help "ERROR: invalid argument for --arch flag"))))
          ((string=? (car args) "--nocolor")
           (lp filename #f arch (cdr args)))
          ((string=? (car args) "--")
           (if (not (= (length args) 2)) (help "ERROR: following -- must be only a filename"))
           (if filename (help "ERROR: you can't have it both ways, use -- or don't"))
           (lp (cadr args) color arch (cddr args)))
          (else
           (if filename (help "ERROR: extra arguments on command line"))
           (lp (car args) color arch (cdr args))))))

(module+ main
  (define (main args)
    (call-with-values (lambda () (parse-args args))
                      disassemble-file))
  (main (cdr (command-line))))
