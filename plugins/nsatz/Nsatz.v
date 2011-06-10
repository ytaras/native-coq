(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2010     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(*
 Tactic nsatz: proofs of polynomials equalities in an integral domain 
(commutative ring without zero divisor).
 
Examples: see test-suite/success/Nsatz.v

*)

Require Import List.
Require Import Setoid.
Require Import BinPos.
Require Import BinList.
Require Import Znumtheory.
Require Export Morphisms Setoid Bool.
Require Export Algebra_syntax.
Require Export Ring2.
Require Export Ring2_initial.
Require Export Ring2_tac.
Require Export Cring.

Declare ML Module "nsatz_plugin".

Class Integral_domain {R : Type}`{Rcr:Cring R} := {
 integral_domain_product:
   forall x y, x * y == 0 -> x == 0 \/ y == 0;
 integral_domain_one_zero: not (1 == 0)}.

Section integral_domain.

Context {R:Type}`{Rid:Integral_domain R}.

Lemma integral_domain_minus_one_zero: ~ - (1:R) == 0.
red;intro. apply integral_domain_one_zero. 
assert (0 == - (0:R)). cring.
rewrite H0. rewrite <- H. cring.
Qed.

Lemma psos_r1b: forall x y:R, x - y == 0 -> x == y.
intros x y H; setoid_replace x with ((x - y) + y); simpl;
 [setoid_rewrite H | idtac]; simpl. cring. cring.
Qed.

Lemma psos_r1: forall x y, x == y -> x - y == 0.
intros x y H; simpl; setoid_rewrite H; simpl; cring.
Qed.

Lemma nsatzR_diff: forall x y:R, not (x == y) -> not (x - y == 0).
intros.
intro; apply H.
simpl; setoid_replace x with ((x - y) + y). simpl.
setoid_rewrite H0.
simpl; cring.
simpl. simpl; cring.
Qed.

(* adpatation du code de Benjamin aux setoides *)
Require Import ZArith.
Require Export Ring_polynom.
Require Export InitialRing.

Definition PolZ := Pol Z.
Definition PEZ := PExpr Z.

Definition P0Z : PolZ := P0 (C:=Z) 0%Z.

Definition PolZadd : PolZ -> PolZ -> PolZ :=
  @Padd  Z 0%Z Zplus Zeq_bool.

Definition PolZmul : PolZ -> PolZ -> PolZ :=
  @Pmul  Z 0%Z 1%Z Zplus Zmult Zeq_bool.

Definition PolZeq := @Peq Z Zeq_bool.

Definition norm :=
  @norm_aux Z 0%Z 1%Z Zplus Zmult Zminus Zopp Zeq_bool.

Fixpoint mult_l (la : list PEZ) (lp: list PolZ) : PolZ :=
 match la, lp with
 | a::la, p::lp => PolZadd (PolZmul (norm a) p) (mult_l la lp)
 | _, _ => P0Z
 end.

Fixpoint compute_list (lla: list (list PEZ)) (lp:list PolZ) :=
 match lla with
 | List.nil => lp
 | la::lla => compute_list lla ((mult_l la lp)::lp)
 end.

Definition check (lpe:list PEZ) (qe:PEZ) (certif: list (list PEZ) * list PEZ) :=
 let (lla, lq) := certif in
 let lp := List.map norm lpe in
 PolZeq (norm qe) (mult_l lq (compute_list lla lp)).


(* Correction *)
Definition PhiR : list R -> PolZ -> R :=
  (Pphi ring0 add mul 
    (InitialRing.gen_phiZ ring0 ring1 add mul opp)).

Definition pow (r : R) (n : nat) := Ring_theory.pow_N 1 mul r (N_of_nat n).

Definition PEevalR : list R -> PEZ -> R :=
   PEeval ring0 add mul sub opp
    (gen_phiZ ring0 ring1 add mul opp)
         nat_of_N pow.

Lemma P0Z_correct : forall l, PhiR l P0Z = 0.
Proof. trivial. Qed.

Lemma Rext: ring_eq_ext add mul opp _==_.
apply mk_reqe. intros. rewrite H ; rewrite H0; cring.
 intros. rewrite H; rewrite H0; cring. 
intros.  rewrite H; cring. Qed.
 
Lemma Rset : Setoid_Theory R _==_.
apply ring_setoid.
Qed.

Definition Rtheory:ring_theory ring0 ring1 add mul sub opp _==_.
apply mk_rt.
apply ring_add_0_l.
apply ring_add_comm.   
apply ring_add_assoc.  
apply ring_mul_1_l.    
apply cring_mul_comm.
apply ring_mul_assoc.
apply ring_distr_l.    
apply ring_sub_def.  
apply ring_opp_def.
Defined.

Lemma PolZadd_correct : forall P' P l,
  PhiR l (PolZadd P P') == ((PhiR l P) + (PhiR l P')).
Proof.
unfold PolZadd, PhiR. intros. simpl.
 refine (Padd_ok Rset Rext (Rth_ARth Rset Rext Rtheory)
           (gen_phiZ_morph Rset Rext Rtheory) _ _ _).
Qed.

Lemma PolZmul_correct : forall P P' l,
  PhiR l (PolZmul P P') == ((PhiR l P) * (PhiR l P')).
Proof.
unfold PolZmul, PhiR. intros. 
 refine (Pmul_ok Rset Rext (Rth_ARth Rset Rext Rtheory)
           (gen_phiZ_morph Rset Rext Rtheory) _ _ _).
Qed.

Lemma R_power_theory
     : Ring_theory.power_theory ring1 mul _==_ nat_of_N pow.
apply Ring_theory.mkpow_th. unfold pow. intros. rewrite Nnat.N_of_nat_of_N. 
reflexivity. Qed.

Lemma norm_correct :
  forall (l : list R) (pe : PEZ), PEevalR l pe == PhiR l (norm pe).
Proof.
 intros;apply (norm_aux_spec Rset Rext (Rth_ARth Rset Rext Rtheory)
           (gen_phiZ_morph Rset Rext Rtheory) R_power_theory)
    with (lmp:= List.nil).
 compute;trivial.
Qed.

Lemma PolZeq_correct : forall P P' l,
  PolZeq P P' = true ->
  PhiR l P == PhiR l P'.
Proof.
 intros;apply
   (Peq_ok Rset Rext (gen_phiZ_morph Rset Rext Rtheory));trivial.
Qed.

Fixpoint Cond0 (A:Type) (Interp:A->R) (l:list A) : Prop :=
  match l with
  | List.nil => True
  | a::l => Interp a == 0 /\ Cond0 A Interp l
  end.

Lemma mult_l_correct : forall l la lp,
  Cond0 PolZ (PhiR l) lp ->
  PhiR l (mult_l la lp) == 0.
Proof.
 induction la;simpl;intros. cring.
 destruct lp;trivial. simpl. cring.
 simpl in H;destruct H.
 rewrite  PolZadd_correct.
 simpl. rewrite PolZmul_correct. simpl. rewrite  H.
 rewrite IHla. cring. trivial.
Qed.

Lemma compute_list_correct : forall l lla lp,
  Cond0 PolZ (PhiR l) lp ->
  Cond0 PolZ (PhiR l) (compute_list lla lp).
Proof.
 induction lla;simpl;intros;trivial.
 apply IHlla;simpl;split;trivial.
 apply mult_l_correct;trivial.
Qed.

Lemma check_correct :
  forall l lpe qe certif,
    check lpe qe certif = true ->
    Cond0 PEZ (PEevalR l) lpe ->
    PEevalR l qe == 0.
Proof.
 unfold check;intros l lpe qe (lla, lq) H2 H1.
 apply PolZeq_correct with (l:=l) in H2.
 rewrite norm_correct, H2.
 apply mult_l_correct.
 apply compute_list_correct.
 clear H2 lq lla qe;induction lpe;simpl;trivial.
 simpl in H1;destruct H1.
 rewrite <- norm_correct;auto.
Qed.

(* fin *)

Lemma pow_not_zero: forall p n, pow p n == 0 -> p == 0.
induction n. unfold pow; simpl. intros. absurd (1 == 0). 
simpl. apply integral_domain_one_zero.
 trivial. setoid_replace (pow p (S n)) with (p * (pow p n)).
intros. 
case (integral_domain_product p (pow p n) H). trivial. trivial. 
unfold pow; simpl. 
clear IHn. induction n; simpl; try cring. 
 rewrite Ring_theory.pow_pos_Psucc. cring. exact Rset.
apply ring_mult_comp.
apply cring_mul_comm.
apply ring_mul_assoc.
Qed.

Lemma Rintegral_domain_pow:
  forall c p r, ~c == 0 -> c * (pow p r) == ring0 -> p == ring0.
intros. case (integral_domain_product c (pow p r) H0). intros; absurd (c == ring0); auto. 
intros. apply pow_not_zero with r. trivial. Qed.   

Definition R2:= 1 + 1.

Fixpoint IPR p {struct p}: R :=
  match p with
    xH => ring1
  | xO xH => 1+1
  | xO p1 => R2*(IPR p1)
  | xI xH => 1+(1+1)
  | xI p1 => 1+(R2*(IPR p1))
  end.

Definition IZR1 z :=
  match z with Z0 => 0
             | Zpos p => IPR p
             | Zneg p => -(IPR p)
  end.

Fixpoint interpret3 t fv {struct t}: R :=
  match t with
  | (PEadd t1 t2) =>
       let v1  := interpret3 t1 fv in
       let v2  := interpret3 t2 fv in (v1 + v2)
  | (PEmul t1 t2) =>
       let v1  := interpret3 t1 fv in
       let v2  := interpret3 t2 fv in (v1 * v2)
  | (PEsub t1 t2) =>
       let v1  := interpret3 t1 fv in
       let v2  := interpret3 t2 fv in (v1 - v2)
  | (PEopp t1) =>
       let v1  := interpret3 t1 fv in (-v1)
  | (PEpow t1 t2) =>
       let v1  := interpret3 t1 fv in pow v1 (nat_of_N t2)
  | (PEc t1) => (IZR1 t1)
  | (PEX n) => List.nth (pred (nat_of_P n)) fv 0
  end.


End integral_domain.

Ltac equalities_to_goal :=
  lazymatch goal with
  |  H: (_ ?x ?y) |- _ =>
          try generalize (@psos_r1 _ _ _ _ _ _ _ _ _ _ _ x y H); clear H
  |  H: (_ _ ?x ?y) |- _ =>
          try generalize (@psos_r1 _ _ _ _ _ _ _ _ _ _ _ x y H); clear H
  |  H: (_ _ _ ?x ?y) |- _ =>
          try generalize (@psos_r1 _ _ _ _ _ _ _ _ _ _ _ x y H); clear H
  |  H: (_ _ _ _ ?x ?y) |- _ =>
          try generalize (@psos_r1 _ _ _ _ _ _ _ _ _ _ _ x y H); clear H
(* extension possible :-) *)
  |  H: (?x == ?y) |- _ =>
          try generalize (@psos_r1 _ _ _ _ _ _ _ _ _ _ _ x y H); clear H
   end.

(* lp est incluse dans fv. La met en tete. *)

Ltac parametres_en_tete fv lp :=
    match fv with
     | (@nil _)          => lp
     | (@cons _ ?x ?fv1) =>
       let res := AddFvTail x lp in
         parametres_en_tete fv1 res
    end.

Ltac append1 a l :=
 match l with
 | (@nil _)     => constr:(cons a l)
 | (cons ?x ?l) => let l' := append1 a l in constr:(cons x l')
 end.

Ltac rev l :=
  match l with
   |(@nil _)      => l
   | (cons ?x ?l) => let l' := rev l in append1 x l'
  end.

Ltac nsatz_call_n info nparam p rr lp kont := 
(*  idtac "Trying power: " rr;*)
  let ll := constr:(PEc info :: PEc nparam :: PEpow p rr :: lp) in
(*  idtac "calcul...";*)
  nsatz_compute ll; 
(*  idtac "done";*)
  match goal with
  | |- (?c::PEpow _ ?r::?lq0)::?lci0 = _ -> _ =>
    intros _;
    set (lci:=lci0);
    set (lq:=lq0);
    kont c rr lq lci
  end.

Ltac nsatz_call radicalmax info nparam p lp kont :=
  let rec try_n n :=
    lazymatch n with
    | 0%N => fail
    | _ =>
        (let r := eval compute in (Nminus radicalmax (Npred n)) in
         nsatz_call_n info nparam p r lp kont) ||
         let n' := eval compute in (Npred n) in try_n n'
    end in
  try_n radicalmax.


Ltac lterm_goal g :=
  match g with
    ?b1 == ?b2 => constr:(b1::b2::nil)
  | ?b1 == ?b2 -> ?g => let l := lterm_goal g in constr:(b1::b2::l)     
  end.

Ltac reify_goal l le lb:=
  match le with
     nil => idtac
   | ?e::?le1 => 
        match lb with
         ?b::?lb1 => (* idtac "b="; idtac b;*)
           let x := fresh "B" in
           set (x:= b) at 1;
           change x with (interpret3 e l); 
           clear x;
           reify_goal l le1 lb1
        end
  end.

Ltac get_lpol g :=
  match g with
  (interpret3 ?p _) == _ => constr:(p::nil)
  | (interpret3 ?p _) == _ -> ?g =>
       let l := get_lpol g in constr:(p::l)     
  end.

Ltac nsatz_generic radicalmax info lparam lvar :=
match goal with
  |- ?g => let lb := lterm_goal g in
(*     idtac "lb"; idtac lb;*)
     match eval red in (list_reifyl (lterm:=lb)) with
     | (?fv, ?le) => 
        let fv := match lvar with
                     (@nil _) => fv
                    | _ => lvar
                  end in
(*         idtac "variables:";idtac fv;*)
        let nparam := eval compute in (Z_of_nat (List.length lparam)) in
        let fv := parametres_en_tete fv lparam in
(*        idtac "variables:"; idtac fv;
        idtac "nparam:"; idtac nparam; *)
        match eval red in (list_reifyl (lterm:=lb) (lvar:=fv)) with
          | (?fv, ?le) => 
(*              idtac "variables:";idtac fv; idtac le; idtac lb;*)
              reify_goal fv le lb;
                match goal with 
                   |- ?g => 
                       let lp := get_lpol g in 
                       let lpol := eval compute in (List.rev lp) in
(*                       idtac "polynomes:"; idtac lpol;*)
                       simpl; intros;
  simpl;
  let SplitPolyList kont :=
    match lpol with
    | ?p2::?lp2 => kont p2 lp2
    | _ => idtac "polynomial not in the ideal"
    end in 

  SplitPolyList ltac:(fun p lp =>
    set (p21:=p) ;
    set (lp21:=lp);
(*    idtac "nparam:"; idtac nparam; idtac "p:"; idtac p; idtac "lp:"; idtac lp; *)
    nsatz_call radicalmax info nparam p lp ltac:(fun c r lq lci => 
      set (q := PEmul c (PEpow p21 r)); 
      let Hg := fresh "Hg" in 
      assert (Hg:check lp21 q (lci,lq) = true); 
      [ (vm_compute;reflexivity) || idtac "invalid nsatz certificate"
      | let Hg2 := fresh "Hg" in 
            assert (Hg2: (interpret3 q fv) == 0);
        [ simpl; 
          generalize (@check_correct _ _ _ _ _ _ _ _ _ _ _ fv lp21 q (lci,lq) Hg);
          let cc := fresh "H" in
             simpl; intro cc; apply cc; clear cc;
          simpl;
          repeat (split;[assumption|idtac]); exact I
        | simpl in Hg2; simpl; 
          apply Rintegral_domain_pow with (interpret3 c fv) (nat_of_N r);
          simpl;
            try apply integral_domain_one_zero;
            try apply integral_domain_minus_one_zero;
            try trivial;
            try exact integral_domain_one_zero;
            try exact integral_domain_minus_one_zero
          || (simpl) || idtac "could not prove discrimination result"
        ]
      ]
) 
)
end end end end .

Ltac nsatz:=
  intros;
  try apply (@psos_r1b _ _ _ _ _ _ _ _ _ _ _);
  match goal with |- (@equality ?r _ _ _) =>
    repeat equalities_to_goal;
    nsatz_generic 6%N 1%Z (@nil r) (@nil r)
  end.

Section test.
Context {R:Type}`{Rid:Integral_domain R}.

Goal forall x y:R, x == x.
nsatz.
Qed.

Goal forall x y:R, x == y -> y*y == x*x.
nsatz.
Qed.

Lemma example3 : forall x y z:R,
  x+y+z==0 ->
  x*y+x*z+y*z==0->
  x*y*z==0 -> x*x*x==0.
Proof.
nsatz.
Qed.
(*
Lemma example5 : forall x y z u v:R,
  x+y+z+u+v==0 ->
  x*y+x*z+x*u+x*v+y*z+y*u+y*v+z*u+z*v+u*v==0->
  x*y*z+x*y*u+x*y*v+x*z*u+x*z*v+x*u*v+y*z*u+y*z*v+y*u*v+z*u*v==0->
  x*y*z*u+y*z*u*v+z*u*v*x+u*v*x*y+v*x*y*z==0 ->
  x*y*z*u*v==0 -> x*x*x*x*x ==0.
Proof.
nsatz.
Qed.
*)
End test.

(* Real numbers *)
Require Import Reals.
Require Import RealField.

Lemma Rsth : Setoid_Theory R (@eq R).
constructor;red;intros;subst;trivial.
Qed.

Instance Rops: (@Ring_ops R 0%R 1%R Rplus Rmult Rminus Ropp (@eq R)).

Instance Rri : (Ring (Ro:=Rops)).
constructor;
try (try apply Rsth;
   try (unfold respectful, Proper; unfold equality; unfold eq_notation in *;
  intros; try rewrite H; try rewrite H0; reflexivity)).
 exact Rplus_0_l. exact Rplus_comm. symmetry. apply Rplus_assoc.
 exact Rmult_1_l.  exact Rmult_1_r. symmetry. apply Rmult_assoc.
 exact Rmult_plus_distr_r. intros; apply Rmult_plus_distr_l. 
exact Rplus_opp_r.
Defined.

Lemma R_one_zero: 1%R <> 0%R.
discrR.
Qed.

Instance Rcri: (Cring (Rr:=Rri)).
red. exact Rmult_comm. Defined.

Instance Rdi : (Integral_domain (Rcr:=Rcri)). 
constructor. 
exact Rmult_integral. exact R_one_zero. Defined.

Goal forall x y:R, x = y -> (x*x-x+1)%R = ((y*y-y)+1+0)%R.
nsatz.
Qed.

(* Rational numbers *)
Require Import QArith.

Check Q_Setoid.

Instance Qops: (@Ring_ops Q 0%Q 1%Q Qplus Qmult Qminus Qopp Qeq).

Instance Qri : (Ring (Ro:=Qops)).
constructor.
try apply Q_Setoid. 
apply Qplus_comp. 
apply Qmult_comp. 
apply Qminus_comp. 
apply Qopp_comp.
 exact Qplus_0_l. exact Qplus_comm. apply Qplus_assoc.
 exact Qmult_1_l.  exact Qmult_1_r. apply Qmult_assoc.
 apply Qmult_plus_distr_l.  intros. apply Qmult_plus_distr_r. 
reflexivity. exact Qplus_opp_r.
Defined.

Lemma Q_one_zero: not (Qeq 1%Q 0%Q).
unfold Qeq. simpl. auto with *. Qed.

Instance Qcri: (Cring (Rr:=Qri)).
red. exact Qmult_comm. Defined.

Instance Qdi : (Integral_domain (Rcr:=Qcri)). 
constructor. 
exact Qmult_integral. exact Q_one_zero. Defined.

Goal forall x y:Q, Qeq x y -> Qeq (x*x-x+1)%Q ((y*y-y)+1+0)%Q.
nsatz.
Qed.

(* Integers *)
Lemma Z_one_zero: 1%Z <> 0%Z.
omega. 
Qed.

Instance Zcri: (Cring (Rr:=Zr)).
red. exact Zmult_comm. Defined.

Instance Zdi : (Integral_domain (Rcr:=Zcri)). 
constructor. 
exact Zmult_integral. exact Z_one_zero. Defined.

Goal forall x y:Z, x = y -> (x*x-x+1)%Z = ((y*y-y)+1+0)%Z.
nsatz. 
Qed.

