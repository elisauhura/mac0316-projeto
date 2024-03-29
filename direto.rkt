#lang plai-typed

#|
 | Variáveis
 |#

(define-type ExprC
  [numC (n : number)]
  [varC  (s : symbol)] ; não é mais identificador
  [plusC (l : ExprC) (r : ExprC)]
  [multC (l : ExprC) (r : ExprC)]
  [divC (l : ExprC) (r : ExprC)]
  [lamC (arg : symbol) (body : ExprC)]
  [appC (fun : ExprC) (arg : ExprC)]
  [ifC   (condição : ExprC) (sim : ExprC) (não : ExprC)]
  [setC (var : symbol) (arg : ExprC)] ; atribuição
  [seqC (b1 : ExprC) (b2 : ExprC)]  ; executa b1 depois b2
  [showC (v : ExprC)]
  )

; inclui os mesmos tipos
(define-type ExprS
  [numS    (n : number)]
  [varS    (s : symbol)] 
  [lamS    (arg : symbol) (body : ExprS)]
  [appS    (fun : ExprS) (arg : ExprS)] 
  [plusS   (l : ExprS) (r : ExprS)]
  [bminusS (l : ExprS) (r : ExprS)]
  [uminusS (e : ExprS)]
  [multS   (l : ExprS) (r : ExprS)]
  [divS   (l : ExprS) (r : ExprS)]
  [ifS     (c : ExprS) (s : ExprS) (n : ExprS)]
  [setS    (var : symbol) (arg : ExprS)]
  [seqS    (b1 : ExprS) (b2 : ExprS)]
  [showS    (v : ExprS)]
  )


; agora é preciso tomar cuidado com as modificações
(define (desugar [as : ExprS]) : ExprC  
  (type-case ExprS as
    [numS    (n) (numC n)]
    [varS    (s) (varC s)]
    [lamS    (a b)  (lamC a (desugar b))] ; idem
    [appS    (fun arg) (appC (desugar fun) (desugar arg))] 
    [plusS   (l r) (plusC (desugar l) (desugar r))] 
    [multS   (l r) (multC (desugar l) (desugar r))] 
    [divS   (l r) (divC (desugar l) (desugar r))]
    [bminusS (l r) (plusC (desugar l) (multC (numC -1) (desugar r)))]
    [uminusS (e)   (multC (numC -1) (desugar e))]
    [ifS     (c s n) (ifC (desugar c) (desugar s) (desugar n))]
    [setS    (s v)   (setC s (desugar v))]
    [seqS    (b1 b2) (seqC (desugar b1) (desugar b2))]
    [showS   (v)     (showC (desugar v))]
    ))


; Precisamos de Storage e Locations
(define-type-alias Location number)

; Não precisamos mais da caixa
(define-type Value
  [numV  (n : number)]
  [closV (arg : symbol) (body : ExprC) (env : Env)])
  

; associar símbolos a localizações
(define-type Binding
        [bind (name : symbol) (val : Location)])

; Env é igual, só mudamos Binding
(define-type-alias Env (listof Binding))
(define mt-env empty)
(define extend-env cons)

; Armazenamento, bem similar
;   bind <-> cell
;   mt-env <-> mt-store
;   extend-env <-> override-store
(define-type Storage
      [cell (location : Location) (val : Value)])
(define-type-alias Store (listof Storage))

(define mt-store empty)
(define override-store cons)

; lookup também muda o tipo de retorno
(define (lookup [for : symbol] [env : Env]) : Location
       (cond
            [(empty? env) (error 'lookup (string-append (symbol->string for) " não foi encontrado"))] ; livre (não definida)
            [else (cond
                  [(symbol=? for (bind-name (first env)))   ; achou!
                                 (bind-val (first env))]
                  [else (lookup for (rest env))])]))        ; vê no resto


; check verifica se precisa criar uma variavel
(define (check [for : symbol] [env : Env]) : boolean
       (cond
            [(empty? env) #f] ; livre (não definida)
            [else (cond
                  [(symbol=? for (bind-name (first env))) #t]   ; achou!
                  [else (check for (rest env))])]))        ; vê no resto


; fetch é o lookup do store
(define (fetch [l : Location] [sto : Store]) : Value
       (cond
            [(empty? sto) (error 'fetch "posição não encontrada")]
            [else (cond
                  [(= l   (cell-location (first sto)))   ; achou!
                                 (cell-val (first sto))]
                  [else (fetch l (rest sto))])]))        ; vê no resto


;; retorna a próxima localização disponível
(define new-loc
   (let ( [ n (box 0)])
        (lambda () 
           (begin
              (set-box! n (+ 1 (unbox n)))
              (unbox n)))))

; novos operadores
(define (num+ [l : Value] [r : Value]) : Value
    (cond
        [(and (numV? l) (numV? r))
             (numV (+ (numV-n l) (numV-n r)))]
        [else
             (error 'num+ "Um dos argumentos não é número")]))

(define (num* [l : Value] [r : Value]) : Value
    (cond
        [(and (numV? l) (numV? r))
             (numV (* (numV-n l) (numV-n r)))]
        [else
             (error 'num* "Um dos argumentos não é número")]))

(define (num/ [l : Value] [r : Value]) : Value
    (cond
        [(and (numV? l) (numV? r))
             (numV (/ (numV-n l) (numV-n r)))]
        [else
             (error 'num* "Um dos argumentos não é número")]))

(define-type Result
      [v*s*e (v : Value) (s : Store) (e : Env)])

; Recebe e devolve o Store..
(define (interp [a : ExprC] [env : Env] [sto : Store]) : Result
  (type-case ExprC a
    [numC (n) (v*s*e (numV n) sto env)] 
    [varC (n)  (v*s*e (fetch (lookup n env) sto) sto env)]  ; busca em cascata, env e em seguida no sto
    [lamC (a b) (v*s*e (closV a b env) sto env)]
    [seqC (b1 b2) (type-case Result (interp b1 env sto)
                    [v*s*e (v-b1 s-b1 e-b1) ; resultado e store retornado por b1
                          (interp b2 e-b1 s-b1)])]
    ; aplicação de função
    [appC (f a)
      (type-case Result (interp f env sto) ; acha a função
         [v*s*e (v-f s-f e-f)
              (type-case Result (interp a env s-f) ; argumento com sto modificado pela função
                 [v*s*e (v-a s-a e-a)
                      (let ([onde (new-loc)]) ; aloca posição para o valor do argumento
                           (let [(result (interp (closV-body v-f) ; corpo
                                   (extend-env (bind (closV-arg v-f) onde) ; com novo argumento
                                       (closV-env v-f))
                                   (override-store (cell onde v-a) s-a)))]
                              (v*s*e (v*s*e-v result) (v*s*e-s result) env)
                            )) ; com novo valor
                  ])])]
    [plusC (l r) 
           (type-case Result (interp l env sto)
               [v*s*e (v-l s-l e-l)
                    (type-case Result (interp r env s-l)
                      [v*s*e (v-r s-r e-r)
                           (v*s*e (num+ v-l v-r) s-r env)])])]
    [multC (l r) 
           (type-case Result (interp l env sto)
               [v*s*e (v-l s-l e-l)
                    (type-case Result (interp r env s-l)
                      [v*s*e (v-r s-r e-l)
                           (v*s*e (num* v-l v-r) s-r env)])])]
     [divC (l r) 
           (type-case Result (interp l env sto)
               [v*s*e (v-l s-l e-l)
                    (type-case Result (interp r env s-l)
                      [v*s*e (v-r s-r e-l)
                           (v*s*e (num/ v-l v-r) s-r env)])])]
    ; ifC já serializa
    [ifC (c s n) (if (zero? (numV-n (v*s*e-v (interp c env sto)))) (interp n env sto) (interp s env sto))]
    

    [setC (var val) (type-case Result (interp val env sto)
                     [v*s*e (v-val s-val e-val)
                         (if (check var env)
                              (let ([onde (lookup var env)]) ; acha a variável
                                   (v*s*e v-val
                                        (override-store ; atualiza
                                        (cell onde v-val) s-val) env))
                              (let [(onde (new-loc))]
                                   (v*s*e v-val 
                                        (override-store (cell onde v-val) s-val)
                                        (extend-env (bind var onde) env)
                                   )
                              )
                         )])]
     [showC (v) (let 
                    ([x (interp v env sto)])
                    (begin (display (v*s*e-v x)) (display "\n") x))]
    ))

; o parser permite definir funções...
(define (parse [s : s-expression]) : ExprS
  (cond
    [(s-exp-number? s) (numS (s-exp->number s))]
    [(s-exp-symbol? s) (varS (s-exp->symbol s))] ; pode ser um símbolo livre nas definições de função
    [(s-exp-list? s)
     (let ([sl (s-exp->list s)])
       (case (s-exp->symbol (first sl))
         [(+) (plusS (parse (second sl)) (parse (third sl)))]
         [(*) (multS (parse (second sl)) (parse (third sl)))]
         [(/) (divS (parse (second sl)) (parse (third sl)))]
         [(-) (bminusS (parse (second sl)) (parse (third sl)))]
         [(~) (uminusS (parse (second sl)))]
         [(func) (lamS (s-exp->symbol (second sl)) (parse (third sl)))] ; definição
         [(call) (appS (parse (second sl)) (parse (third sl)))]
         [(if) (ifS (parse (second sl)) (parse (third sl)) (parse (fourth sl)))]
         [(:=) (setS (s-exp->symbol (second sl)) (parse (third sl)))]
         [(seq) (seqS (parse (second sl)) (parse (third sl)))]
         [(print) (showS (parse (second sl)))]
         [else (error 'parse "invalid list input")]))]
    [else (error 'parse "invalid input")]))

; Facilitador
(define (interpS [s : s-expression]) (interp (desugar (parse s)) mt-env mt-store))

; Testes
; (test (v*s-v (interp (plusC (numC 10) (appC (lamC '_ (numC 5)) (numC 10)))
;              mt-env mt-store))
;      (numV 15))

; (interpS '(+ 10 (call (func x (+ x x)) 16)))



; (interpS '(call (func x (seq (:= x (+ x 10)) x))  32)) 


