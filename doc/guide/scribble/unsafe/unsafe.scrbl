#lang scribble/manual

@(require (for-label racket) scribble/core scribble/eval)
@(require (for-label rosette/base/define rosette/query/tools rosette/query/eval rosette/solver/solution
                     rosette/base/term (only-in rosette/query/debug define/debug debug)
                     (only-in rosette/base/safe assert) ))
@(require (only-in "../refs.scrbl" ~cite rosette:pldi14))
@(require "../util/lifted.rkt")

@(define rosette-eval (rosette-evaluator))

@title[#:tag "ch:unsafe"]{Unsafe Operations}

Throughout this guide, we have assumed that Rosette programs are 
written in the @racket[rosette/safe] dialect of the full language.  
This dialect extends a core subset of Racket with @seclink["ch:essentials"]{solver-aided 
functionality}.  In this chapter, we briefly discuss the @racket[rosette] 
dialect of the language, which exports all of Racket.  

Safe use of the full @racket[rosette] language requires a basic understanding 
of how Rosette's Symbolic Virtual Machine (SVM) works  @~cite[rosette:pldi14].  
Briefly, the SVM hijacks the normal Racket execution for all procedures and 
constructs that are exported by @racket[rosette/safe].  Any programs that are 
implemented exclusively in the @racket[rosette/safe] language are therefore 
fully under the SVM's control.  This means that the SVM can correctly interpret 
the application of a procedure or a macro to a symbolic value, and it 
can correctly handle any side-effects (in particular, writes to memory) performed 
by @racket[rosette/safe] code.

The following snippet demonstrates the non-standard execution that the SVM needs to 
perform in order to assign the expected meaning to Rosette code:
@interaction[#:eval rosette-eval
(define y (vector 0 1 2))
 
(define-symbolic b boolean?)

(code:comment "If b is true, then y[1] should be 3, otherwise y[2] should be 4:")
(if b
    (vector-set! y 1 3)
    (vector-set! y 2 4))

(code:comment "The state of y correctly accounts for both possibilities:")
(code:comment " * If the solver finds that b must be #t, then the contents of y will be #(0 3 2).")
(code:comment " * Otherwise, the contents of y will be #(0 1 4)")

y

(define env1 (solve (assert b)))
(evaluate y env1)

(define env2 (solve (assert (not b))))
(evaluate y env2)]

Because the SVM only controls the execution of @racket[rosette/safe] code, 
it cannot, in general, guarantee the safety or correctness of arbitrary @racket[rosette] programs. 
As soon as a @racket[rosette] program calls an @tech[#:key "lifted construct"]{unlifted} Racket construct  
(that is, a procedure or a macro not implemented in or provided by the @racket[rosette/safe] language), 
the execution escapes back to the Racket interpreter.  The SVM has no control over the side-effects 
performed by the Racket interpreter, or the meaning that it (perhaps incorrectly) assigns to programs 
in the presence of symbolic values.  As a result, the programmer is responsible for ensuring that 
a @racket[rosette] program continues to behave correctly after the execution returns from the Racket interpreter.

As an example of incorrect behavior, consider the following @racket[rosette] snippet.  
The procedures @racket[make-hash], @racket[hash-ref], and @racket[hash-clear!] are not in @racket[rosette/safe].
Whenever they are invoked, the execution escapes to the Racket interpreter.

@(rosette-eval '(require (only-in racket make-hash hash-clear! hash-ref)))
@defs+int[#:eval rosette-eval

[(define h (make-hash '((1 . 2))))
(define-symbolic key number?)
(define-symbolic b boolean?)]


(code:comment "The following call produces an incorrect value. Intuitively, we expect the")
(code:comment "output to be the symbolic number that is either 2 or 0, depending on whether")
(code:comment "the key is 1 or something else.")

(hash-ref h key 0)

(code:comment "The following call produces an incorrect state. Intuitively, we expect h")
(code:comment "to be empty if b is true and unchanged otherwise.")
(when b
  (hash-clear! h))
h]  

When is it safe to use a Racket procedure or macro?  The answer depends on their semantics.  
A conservative rule is to only use an unlifted construct @var[c] in an @deftech{effectively concrete} @tech{program state}. 
The SVM is in such a state when 
@itemlist[#:style 'ordered
  @item{the current @tech{path condition} is @racket[#t];}
  @item{the @tech{assertion store} is empty; and,}
  @item{all local and global variables that may be read by @var[c] contain @deftech{fully concrete value}s. A  
value (e.g., a list) is fully concrete if no symbolic values can be reached by recursively traversing its structure.}] 
The two uses of @racket[hash-ref] and @racket[hash-clear!] in our buggy example violate the third and first 
requirements, respectively.

Being conservative, the above rule disallows many scenarios in which it is still safe to use 
Racket constructs.  These, however, have to be considered on a case-by-case basis.  For example, 
it is safe to use Racket's iteration and comprehension constructs, such as @racket[for] or @racket[for/list], 
as long as they iterate over concrete sequences, and all guard expressions produce fully concrete values in 
each iteration.  In practice, Rosette programs can safely use many common Racket constructs, and with a 
bit of experience, it becomes easy to see when it is okay to break the effectively-concrete rule.