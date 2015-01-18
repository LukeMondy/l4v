(*
 * Copyright 2014, NICTA
 *
 * This software may be distributed and modified according to the terms of
 * the BSD 2-Clause license. Note that NO WARRANTY is provided.
 * See "LICENSE_BSD2.txt" for details.
 *
 * @TAG(NICTA_BSD)
 *)

theory Memcpy
imports
  "../../../c-parser/CTranslation"
  "../../AutoCorres"
begin

(* Helper for noticing when you accidentally haven't constrained an of_nat *)
abbreviation "of_nat32 \<equiv> of_nat::(nat \<Rightarrow> word32)"

lemma byte_ptr_guarded:
    "ptr_val (x::8 word ptr) \<noteq> 0 \<Longrightarrow> c_guard x"
  unfolding c_guard_def c_null_guard_def ptr_aligned_def
  by (clarsimp simp: intvl_Suc)

(* FIXME: MOVE *)
lemma ptr_add_coerce: "ptr_val (((ptr_coerce x)::('a::{c_type}) ptr) +\<^sub>p a) = (ptr_val x) + (of_int a * of_nat (size_of TYPE('a)))"
  apply (case_tac x)
  apply (clarsimp simp: CTypesDefs.ptr_add_def)
  done

(* FIXME: MOVE *)
(* Casting a valid pointer to char* and incrementing it by a value less than
 * the size of the underlying type does not give us NULL.
 *)
lemma ptr_contained:"\<lbrakk> c_guard (x::('a::c_type) ptr); size_of TYPE('a) = sz;
                       0 \<le> i; i < int sz; (y::8 word ptr) = ptr_coerce x\<rbrakk> \<Longrightarrow> c_guard (y +\<^sub>p i)"
  apply (rule byte_ptr_guarded)
  unfolding c_guard_def c_null_guard_def ptr_add_def
  apply simp
  apply (clarsimp simp: CTypesDefs.ptr_add_def intvl_def)
  apply (erule allE [where x="nat i"])
  apply (clarsimp simp: nat_less_iff of_nat_nat)
  done

install_C_file "memcpy.c"

(* FIXME: MOVE *)
lemma squash_auxupd_id[polish]:
  "modify (t_hrs_'_update (hrs_htd_update id)) = skip"
  by (monad_eq simp: skip_def id_def hrs_htd_update_def)

autocorres [no_heap_abs=memcpy] "memcpy.c"

(* Dereference a pointer *)
abbreviation "deref s x \<equiv> h_val (hrs_mem (t_hrs_' s)) x"

(* char* cast *)
abbreviation "byte_cast x \<equiv> ((ptr_coerce x)::8 word ptr)"

context memcpy begin

lemma memcpy_char:
  "\<lbrace> \<lambda>s. c_guard (x::8 word ptr) \<and>
         c_guard (y::8 word ptr) \<and>
         unat sz = size_of TYPE(8 word) \<and>
         P (deref s x) \<and>
         x \<noteq> y\<rbrace>
      memcpy' (ptr_coerce y) (ptr_coerce x) sz
   \<lbrace>\<lambda> _ s. P (deref s y) \<rbrace>!"
  (* Evaluate sz *)
  apply clarsimp

  unfolding memcpy'_def
  apply (clarsimp simp:skip_def)
  apply wp

  (* Unroll the loop twice *)
  apply (subst whileLoop_unroll, wp)
     apply (subst whileLoop_unroll, wp)

  (* The remaining loop is never encountered *)
       apply (rule validNF_false_pre)
      apply wp

  (* Finally we're left with the single assignment *)
  apply (clarsimp simp:hrs_mem_update h_val_heap_update)
  apply unat_arith
 done

lemma is_aligned_add_not_aligned:
    "\<lbrakk>is_aligned (p::word32) n; \<not> is_aligned (q::word32) n\<rbrakk> \<Longrightarrow>
          \<not> is_aligned (p + q) n"
  by (metis is_aligned_addD1)

(* Possibly useful for something later *)
lemma "\<lbrakk> 2 ^ n dvd (p::nat); n > 0; i > 0; i < 2 ^ n; p + i > p; n < 32\<rbrakk> \<Longrightarrow>
          \<not> (2 ^ n dvd (p + i))"
  by (metis dvd_def dvd_reduce_multiple nat_dvd_not_less)

(* FIXME: MOVE *)
lemma word32_gr0_conv_Suc:"(m::word32) > 0 \<Longrightarrow> \<exists>n. m = n + 1"
  by (metis comm_semiring_1_class.normalizing_semiring_rules(24) zadd_diff_inverse)

(* FIXME: MOVE *)
lemma offset_not_aligned:
  "\<lbrakk> is_aligned (p::word32) n; i > 0; i < 2 ^ n; n < 32\<rbrakk>
     \<Longrightarrow> \<not> is_aligned (p + of_nat i) n"
  apply (erule is_aligned_add_not_aligned)
  unfolding is_aligned_def apply clarsimp
  apply (subst (asm) unat_of_nat_len)
   apply (metis len32 unat_less_word_bits unat_power_lower32 word_bits_conv)
  apply (metis nat_dvd_not_less)
  done

lemma of_nat_prop_exp: "n < 32 \<Longrightarrow> of_nat (2 ^ n) = 2 ^ (of_nat n)"
  by clarsimp

lemma neg_mask_add_aligned:
  "\<lbrakk> is_aligned p n; q < 2 ^ n \<rbrakk>
     \<Longrightarrow> (p + q) && ~~ mask n = p && ~~ mask n"
  by (metis is_aligned_add_helper is_aligned_neg_mask_eq)

lemma neq_imp_bytes_disjoint:
  "\<lbrakk> c_guard (x::'a::c_type ptr); c_guard y; unat j < align_of TYPE('a);
        unat i < align_of TYPE('a); x \<noteq> y; 2 ^ n = align_of TYPE('a); n < 32\<rbrakk> \<Longrightarrow>
    ptr_val x + j \<noteq> ptr_val y + i"
  apply (rule ccontr)
  apply (subgoal_tac "is_aligned (ptr_val x) n")
   apply (subgoal_tac "is_aligned (ptr_val y) n")
    apply (subgoal_tac "(ptr_val x + j && ~~ mask n) = (ptr_val y + i && ~~ mask n)")
     apply (subst (asm) neg_mask_add_aligned, simp, simp add: word_less_nat_alt)
     apply (subst (asm) neg_mask_add_aligned, simp, simp add: word_less_nat_alt)
     apply (clarsimp simp: is_aligned_neg_mask_eq)
    apply simp
   apply (clarsimp simp: c_guard_def ptr_aligned_def is_aligned_def)
  apply (clarsimp simp: c_guard_def ptr_aligned_def is_aligned_def)
  done

lemma from_bytes_eq [simp]:
  "from_bytes [x] = x"
  apply (clarsimp simp:from_bytes_def update_ti_t_def typ_info_word)
  apply (simp add:word_rcat_def)
  apply (simp add:bin_rcat_def)
  by (metis len8 word_of_int_uint word_ubin.Abs_norm)

lemma memcpy_word:
  "\<lbrace> \<lambda>s. c_guard (x::32 word ptr) \<and>
         c_guard (y::32 word ptr) \<and>
         unat sz = size_of TYPE(32 word) \<and>
         P (deref s x) \<and>
         x \<noteq> y \<rbrace>
      memcpy' (ptr_coerce y) (ptr_coerce x) sz
   \<lbrace> \<lambda>_ s. P (deref s y) \<rbrace>!"
  apply clarsimp
  unfolding memcpy'_def apply (clarsimp simp:skip_def)
  apply (rule validNF_assume_pre)
  apply (subgoal_tac "{ptr_val x ..+ unat sz} \<inter> {ptr_val y ..+ unat sz} = {}")
   apply (subst whileLoop_add_inv [where
     I="\<lambda>i s.  unat i \<le> unat sz \<and>
                (\<forall>a < i. deref s (byte_cast x +\<^sub>p uint a) = deref s (byte_cast y +\<^sub>p uint a)) \<and>
                P (deref s x)" and
     M="\<lambda>(i, s). unat sz - unat i"])
   apply (wp validNF_whileLoop_inv_measure_twosteps)
      apply clarsimp
      apply (rule conjI, unat_arith)
      apply (rule conjI, clarsimp)
       apply (case_tac "a = i")
        apply (clarsimp)
        apply (erule_tac x=i in allE)
        apply (clarsimp simp:hrs_mem_update h_val_heap_update)
        apply (subst h_val_heap_same)
            apply (rule ptr_retyp_h_t_valid)
            apply simp
           apply (rule ptr_retyp_disjoint)
            apply (rule ptr_retyp_h_t_valid)
            apply simp
           apply (clarsimp simp:ptr_add_def intvl_def CTypesDefs.ptr_add_def)
          apply simp
         apply (clarsimp simp: CTypesDefs.ptr_add_def field_of_t_simple)
         apply (drule field_of_t_simple)
         apply clarsimp
        apply simp
       apply (subgoal_tac "a < i")
        apply (clarsimp simp:hrs_mem_update)
        apply (subst h_val_heap_update_disjoint)

         (* The current goal should be obvious to unat_arith, but for some reason isn't *)
         apply (clarsimp simp:ptr_add_def intvl_def ptr_val_def disjoint_iff_not_equal)
         apply (erule_tac x="ptr_val x + a" in allE, clarsimp)
         apply (erule impE)
          apply (rule_tac x="unat a" in exI, clarsimp)
          apply unat_arith
          
         apply (erule_tac x="ptr_val y + i" and
                          P="\<lambda>ya. (\<exists>k. ya = ptr_val y + of_nat k \<and> k < 4) \<longrightarrow> ptr_val y + i \<noteq> ya" in allE, clarsimp)
         apply (erule_tac x="unat i" in allE, clarsimp)
          apply unat_arith
         apply (clarsimp simp:CTypesDefs.ptr_add_def)
        apply (subst h_val_heap_update_disjoint)
         (* Similar goal to the previous irritation, but this time Isabelle decides to play ball *)
         apply (clarsimp simp:ptr_add_def intvl_def ptr_val_def disjoint_iff_not_equal)
        apply (clarsimp simp:CTypesDefs.ptr_add_def)
       apply (clarsimp simp:CTypesDefs.ptr_add_def)
      apply unat_arith

      apply (rule conjI)
       apply (subst hrs_mem_update)+
       apply (subst h_val_heap_update_disjoint)
        apply (clarsimp simp: disjoint_iff_not_equal)
        apply (clarsimp simp:CTypesDefs.ptr_add_def intvl_def)
        apply (erule_tac x="ptr_val x + of_nat k" in allE)
        apply (erule impE)
         apply (rule_tac x="k" in exI)
         apply simp
        apply (erule_tac x="ptr_val y + i" and
                         P="\<lambda>ya. (\<exists>k. ya = ptr_val y + of_nat k \<and> k < 4) \<longrightarrow> ptr_val x + of_nat k \<noteq> ya" in allE)
        apply (erule impE)
         apply (rule_tac x="unat i" in exI)
         apply simp
         apply unat_arith
        apply simp
       apply simp

      (* Yet more tedium that unat_arith doesn't like *)
      apply (rule conjI)
       apply (rule byte_ptr_guarded,
              clarsimp simp:CTypesDefs.ptr_add_def c_guard_def c_null_guard_def intvl_def,
              (erule_tac x="unat i" in allE)+,
              clarsimp,
              unat_arith)+

     apply wp
     apply unat_arith
    apply clarsimp
    apply (subgoal_tac "deref sa x = deref sa y")
     apply clarsimp
    apply (clarsimp simp: h_val_def)[1]
    apply (rule arg_cong[where f=from_bytes])
    apply (subst numeral_eqs(3))+
    apply simp
    apply (rule_tac x=0 in allE, assumption, erule impE, unat_arith)
    apply (rule_tac x=1 in allE, assumption, erule impE, unat_arith)
    apply (rule_tac x=2 in allE, assumption, erule impE, unat_arith)
    apply (rule_tac x=3 in allE, assumption, erule impE, unat_arith)
    apply (simp add:CTypesDefs.ptr_add_def)
    apply (metis comm_semiring_1_class.normalizing_semiring_rules(24))
   apply clarsimp
   apply clarsimp
  apply (clarsimp simp:intvl_def disjoint_iff_not_equal)
  apply (drule_tac x=x and y=y and j="of_nat k" and i="of_nat ka" and n=2 in neq_imp_bytes_disjoint)
        apply assumption
       apply (case_tac "k = 0", clarsimp) (* insert "k > 0" *)
       apply (clarsimp simp:unat_of_nat_len)
      apply (case_tac "ka = 0", clarsimp)
      apply (clarsimp simp:unat_of_nat_len)
     apply assumption
    apply clarsimp+
  done

text {* The bytes at the pointer @{term p} are @{term bs}. *}
definition
  bytes_at :: "'a globals_scheme \<Rightarrow> 'b::c_type ptr \<Rightarrow> word8 list \<Rightarrow> bool"
where
  "bytes_at s p bs \<equiv> length bs = 0 \<or>
                      (length bs \<le> UINT_MAX \<and> (\<forall>i \<in> {0..(length bs - 1)}. deref s (byte_cast p +\<^sub>p (of_nat i)) = bs ! i))"

lemma bytes_at_none[simp]: "bytes_at s p []"
  by (clarsimp simp:bytes_at_def)

text {* The bytes of typed pointer @{term p} are @{term bs}. *}
definition
  bytes_of :: "'a globals_scheme \<Rightarrow> 'b::c_type ptr \<Rightarrow> word8 list \<Rightarrow> bool"
where
  "bytes_of s p bs \<equiv> length bs = size_of TYPE('b) \<and> bytes_at s p bs"

text {* The bytes at a char pointer are just it dereferenced. *}
lemma bytes_of_char[simp]: "bytes_of s (p::8word ptr) bs = (length bs = 1 \<and> deref s p = hd bs)"
  apply (clarsimp simp:bytes_of_def bytes_at_def)
  apply (rule iffI)
   apply clarsimp
   apply (erule disjE)
    apply clarsimp+
   apply (rule hd_conv_nth[symmetric])
   apply clarsimp+
  apply (clarsimp simp:UINT_MAX_def)
  apply (subgoal_tac "hd bs = bs ! 0")
   apply simp
  apply (rule hd_conv_nth)
  apply clarsimp
  done

text {* A pointer does not wrap around memory. *}
definition
  no_wrap :: "'a::c_type ptr \<Rightarrow> nat \<Rightarrow> bool"
where
  "no_wrap p sz \<equiv> 0 \<notin> {ptr_val p ..+ sz}"

text {* Two pointers do not overlap. *}
definition
  no_overlap :: "'a::c_type ptr \<Rightarrow> 'b::c_type ptr \<Rightarrow> nat \<Rightarrow> bool"
where
  "no_overlap p q sz \<equiv> {ptr_val p ..+ sz} \<inter> {ptr_val q ..+ sz} = {}"

lemma no_overlap_sym: "no_overlap x y = no_overlap y x"
  apply (rule ext)
  apply (clarsimp simp:no_overlap_def)
  by blast

(* FIXME: MOVE *)
lemma h_val_not_id:
  fixes x :: "'a::mem_type ptr"
    and y :: "'b::mem_type ptr"
  shows "{ptr_val x..+size_of TYPE('a)} \<inter> {ptr_val y..+size_of TYPE('b)} = {}
     \<Longrightarrow> h_val (hrs_mem (hrs_mem_update (heap_update x v) s)) y = h_val (hrs_mem s) y"
  apply (subst hrs_mem_heap_update[symmetric])
  apply (subst h_val_heap_update_disjoint)
   apply blast
  apply clarsimp
  done

definition
  update_bytes :: "'a globals_scheme \<Rightarrow> 'b::mem_type ptr \<Rightarrow> word8 list \<Rightarrow> 'a globals_scheme"
where
  "update_bytes s p bs \<equiv> s\<lparr>t_hrs_' := hrs_mem_update (heap_update_list (ptr_val p) bs) (t_hrs_' s)\<rparr>"

lemma the_horse_says_neigh: "(s\<lparr>t_hrs_' := x\<rparr> = s\<lparr>t_hrs_' := y\<rparr>) = (x = y)"
 by (metis (erased, lifting) globals.cases_scheme globals.select_convs(1) globals.update_convs(1))

lemma upto_singleton[simp]:"[x..x] = [x]"
  by (simp add: upto_rec1)

lemma update_bytes_ignore_ptr_coerce[simp]: "update_bytes s (ptr_coerce p) = update_bytes s p"
  by (clarsimp simp:update_bytes_def intro!:ext)

lemma hrs_mem_update_commute:
  "f \<circ> g = g \<circ> f \<Longrightarrow> hrs_mem_update f (hrs_mem_update g s) = hrs_mem_update g (hrs_mem_update f s)"
  by (metis (no_types, lifting) comp_eq_elim hrs_htd_def hrs_htd_mem_update hrs_mem_def hrs_mem_f prod.collapse)

lemma hrs_mem_update_collapse:
  "hrs_mem_update f (hrs_mem_update g s) = hrs_mem_update (f \<circ> g) s"
  by (metis comp_eq_dest_lhs hrs_htd_def hrs_htd_mem_update hrs_mem_def hrs_mem_f prod.collapse)

lemma update_bytes_reorder:
  "{ptr_val p..+length cs} \<inter> {ptr_val q..+length bs} = {} \<Longrightarrow>
      update_bytes (update_bytes s q bs) p cs = update_bytes (update_bytes s p cs) q bs"
  apply (clarsimp simp:update_bytes_def)
  apply (subst the_horse_says_neigh)
  apply (subst hrs_mem_update_commute)
   apply (clarsimp intro!:ext)
   apply (subst heap_update_list_commute)
    apply clarsimp+
  done

lemma lt_step_down: "\<lbrakk>(x::nat) < y; x = y - 1 \<longrightarrow> P; x < y - 1 \<longrightarrow> P\<rbrakk> \<Longrightarrow> P"
  by force

(* XXX: This proof makes me sad. *)
lemma under_uint_imp_no_overflow: "x < UINT_MAX \<Longrightarrow> ((of_nat x)::word32) + 1 \<noteq> 0"
  apply (induct x)
   apply (clarsimp simp:UINT_MAX_def)+
  apply unat_arith
  apply (clarsimp simp:UINT_MAX_def)
  apply (cut_tac y=x and z="(of_nat (UINT_MAX - 1))::word32" in le_unat_uoi)
   apply (clarsimp simp:UINT_MAX_def)+
  done

lemma heap_update_list_append3:
  "1 + length ys < 2 ^ word_bits \<Longrightarrow>
    heap_update_list s (y # ys) hp = heap_update_list s [y] (heap_update_list (s + 1) ys hp)"
  apply clarsimp
  apply (subst heap_update_list_append2[where xs="[y]", simplified])
   apply clarsimp+
  done

lemma hrs_mem_update_cong': "f = g \<Longrightarrow> hrs_mem_update f s = hrs_mem_update g s"
  by presburger

lemma update_bytes_append: "length bs \<le> UINT_MAX \<Longrightarrow>
  update_bytes s p (b # bs) = update_bytes (update_bytes s p [b]) (byte_cast p +\<^sub>p 1) bs"
  apply (clarsimp simp:update_bytes_def)
  apply (subst the_horse_says_neigh)
  apply (subst hrs_mem_update_commute)
   apply (rule ext)+
   apply simp
   apply (case_tac "xa = ptr_val p")
    apply (clarsimp simp:fun_upd_def)
    apply (subst heap_update_nmem_same)
     apply (clarsimp simp:intvl_def ptr_add_def)
     apply (subgoal_tac "k < UINT_MAX")
      prefer 2
      apply unat_arith
     apply (drule under_uint_imp_no_overflow)
     apply unat_arith
    apply clarsimp
   apply (subst heap_update_list_update)
    apply simp
   apply (clarsimp simp:fun_upd_def)
  apply (subst hrs_mem_update_collapse)
  apply (rule hrs_mem_update_cong')
  apply (clarsimp simp:ptr_add_def) 
  apply (rule ext)
  apply (cut_tac xs="[b]" and ys=bs and s="ptr_val p" and hp=x in heap_update_list_append)
  apply (clarsimp simp:fun_upd_def intro!:ext)
  apply (rule conjI)
   apply clarsimp
   apply (subst heap_update_nmem_same)
    apply (clarsimp simp:ptr_add_def intvl_def)
    apply (subgoal_tac "k < UINT_MAX")
     prefer 2
     apply unat_arith
    apply (drule under_uint_imp_no_overflow)
    apply unat_arith
   apply clarsimp
  apply clarsimp
  apply (case_tac "xa \<in> {ptr_val p + 1..+length bs}")
  apply (subst heap_update_mem_same_point)
    apply simp
   apply (subgoal_tac "addr_card = UINT_MAX + 1")
    apply clarsimp
   apply (clarsimp simp:addr_card UINT_MAX_def)
  apply (subst heap_update_mem_same_point)
    apply simp
   apply (subgoal_tac "addr_card = UINT_MAX + 1")
    apply clarsimp
   apply (clarsimp simp:addr_card UINT_MAX_def)
  apply clarsimp
  apply (subst heap_update_nmem_same)
   apply clarsimp
  apply (subst heap_update_nmem_same)
   apply clarsimp+
  done

lemma h_val_not_id_general:
  fixes y :: "'a::mem_type ptr"
  shows "\<forall>i \<in> {0..+size_of TYPE('a)}. \<forall>g. f g (ptr_val y + i) = g (ptr_val y + i)
     \<Longrightarrow> h_val (hrs_mem (hrs_mem_update f s)) y = h_val (hrs_mem s) y"
  apply (subst hrs_mem_update)
  apply (clarsimp simp:h_val_def)
  apply (subgoal_tac "heap_list (f (hrs_mem s)) (size_of TYPE('a)) (ptr_val y) =
                      heap_list (hrs_mem s) (size_of TYPE('a)) (ptr_val y)")
   apply clarsimp
  apply (cut_tac h="f (hrs_mem s)" and p="ptr_val y" and n="size_of TYPE('a)"
                 and h'="hrs_mem s" in heap_list_h_eq2)
   apply (erule_tac x="x - ptr_val y" in  ballE)
    apply clarsimp
   apply (clarsimp simp:intvl_def)+
  done

lemma h_val_not_id_list:
  fixes y :: "'a::mem_type ptr"
  shows "{x..+length vs} \<inter> {ptr_val y..+size_of TYPE('a)} = {}
     \<Longrightarrow> h_val (hrs_mem (hrs_mem_update (heap_update_list x vs) s)) y = h_val (hrs_mem s) y"
  apply (subst h_val_not_id_general)
   apply clarsimp
   apply (metis (erased, hide_lams) disjoint_iff_not_equal heap_update_nmem_same intvlD intvlI
          monoid_add_class.add.left_neutral)
  apply clarsimp
  done

lemma h_val_id_update_bytes:
  fixes q :: "'a::mem_type ptr"
  shows "{ptr_val q..+size_of TYPE('a)} \<inter> {ptr_val p..+length bs} = {}
          \<Longrightarrow> deref (update_bytes s p bs) q = deref s q"
  apply (clarsimp simp:update_bytes_def)
  apply (subst h_val_not_id_list)
   apply blast
  by simp

text {*
  Memcpy does what it says on the box.
  TODO: To be usable in a composed proof, this really needs to state the exact side-effects of
        memcpy.
*}
lemma
  fixes src :: "'a::mem_type ptr"
    and dst :: "'b::mem_type ptr"
  shows "\<forall>s0 bs.
  \<lbrace>\<lambda>s. s = s0 \<and> c_guard src \<and> c_guard dst \<and> sz = of_nat (length bs) \<and> bytes_at s src bs \<and>
       no_wrap src (unat sz) \<and> no_wrap dst (unat sz) \<and> no_overlap src dst (unat sz)\<rbrace>
    memcpy' (ptr_coerce dst) (ptr_coerce src) sz
  \<lbrace>\<lambda>r s. r = ptr_coerce dst \<and> bytes_at s dst bs\<rbrace>!"
  apply (rule allI)+
  apply (rule validNF_assume_pre)
  unfolding memcpy'_def
  apply clarsimp
  apply (subst whileLoop_add_inv[where
    I="\<lambda>i s. unat i \<le> unat sz \<and>
             bytes_at s dst (take (unat i) bs) \<and>
             bytes_at s src bs" and
    M="\<lambda>(i, s). unat sz - unat i"])
  apply wp
    apply clarsimp
    apply (rule conjI)
     apply unat_arith
    apply (rule conjI)
     apply (simp add:bytes_at_def)
     apply (case_tac "bs = []")
      apply (rule disjI1)
      apply clarsimp
     apply (rule disjI2)
     apply clarsimp
     apply (rule conjI)
      apply unat_arith
     apply clarsimp
     apply (case_tac "unat i = ia")
      apply clarsimp
      apply (subgoal_tac "int (unat i) = uint i")
       prefer 2
       apply (subst uint_nat)
       apply simp
      apply simp
      apply (subst h_val_id)
      apply (erule_tac x="unat i" and P="\<lambda>x. deref s (byte_cast src +\<^sub>p int x) = bs ! x" in ballE)
       apply clarsimp
       apply (subst nth_take)
        apply unat_arith
       apply simp
      apply (erule disjE)
       apply clarsimp+
     apply (erule disjE)
      apply (subgoal_tac "length bs \<noteq> 0")
       prefer 2
       apply clarsimp
      apply (case_tac "unat i = 0")
       apply unat_arith
      apply linarith
     apply (subst h_val_not_id)
      apply (clarsimp simp:ptr_add_def intvl_def)
      (* Isabelle, why do you have to make it so hard? *)
      apply (erule_tac P="unat (of_nat ia) = ia" in notE)
      apply (cut_tac y=ia and z="(of_nat UINT_MAX)::word32" in le_unat_uoi)
       apply (subgoal_tac "unat ((of_nat UINT_MAX)::word32) = UINT_MAX")
        prefer 2
        apply (simp add:UINT_MAX_def)
       apply unat_arith
      apply clarsimp
     apply clarsimp
     apply (erule_tac x=ia and A="{0..min (length bs) (unat i) - Suc 0}" in ballE)
      apply clarsimp
      apply (subst nth_take, unat_arith)+
      apply simp
     apply clarsimp
     apply unat_arith
    apply (rule conjI)
     apply (clarsimp simp:bytes_at_def)
     apply (subst h_val_not_id)
      apply (clarsimp simp:no_overlap_def)
      apply (subgoal_tac "ptr_val (byte_cast dst +\<^sub>p uint i) \<in> {ptr_val dst..+unat (of_nat (length bs))}")
       prefer 2
       apply (clarsimp simp:ptr_add_def intvl_def)
       apply (rule_tac x="unat i" in exI)
       apply clarsimp
       apply unat_arith
      (* More or less symmetric subgoal *)
      apply (subgoal_tac "ptr_val (byte_cast src +\<^sub>p int ia) \<in> {ptr_val src..+unat ((of_nat (length bs))::word32)}")
       prefer 2
       apply (clarsimp simp:ptr_add_def intvl_def)
       apply (rule_tac x=ia in exI)
       apply clarsimp
       apply (subgoal_tac "unat ((of_nat (length bs))::word32) = length bs")
        apply clarsimp
        apply arith
       apply (cut_tac y="length bs" and z="(of_nat UINT_MAX)::word32" in le_unat_uoi)
        apply (clarsimp simp:UINT_MAX_def)
       apply arith
      apply (clarsimp simp:intvl_def ptr_add_def)
      apply blast
     apply clarsimp
    apply (rule conjI)
     apply unat_arith
    apply (rule conjI)
     apply (rule byte_ptr_guarded)
     apply (clarsimp simp:no_wrap_def intvl_def ptr_add_def)
     apply (erule_tac x="unat i" in allE)
     apply clarsimp
    apply (rule byte_ptr_guarded)
    apply (clarsimp simp:no_wrap_def intvl_def ptr_add_def)
    apply (erule_tac x="unat i" and
                     P="\<lambda>x. ptr_val dst + ((of_nat x)::word32) = 0 \<longrightarrow> \<not> x < unat ((of_nat (length bs))::word32)"
                    in allE)
    apply clarsimp
   apply clarsimp
   apply (subgoal_tac "unat i = length bs")
    apply clarsimp
   apply (case_tac "length bs = 0")
    apply clarsimp
   apply (subgoal_tac "length bs \<le> UINT_MAX")
    prefer 2
    apply (clarsimp simp:bytes_at_def)
   (* XXX: We keep introducing this subgoal; we should do it once and for all up top. *)
   apply (subgoal_tac "unat ((of_nat (length bs))::word32) = length bs")
    prefer 2
    apply (cut_tac y="length bs" and z="(of_nat UINT_MAX)::word32" in le_unat_uoi)
     apply (clarsimp simp:UINT_MAX_def)
    apply clarsimp+
   apply unat_arith
  apply clarsimp
  done

end

end
