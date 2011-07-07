(************************************************************************)
(*  v      *   The Coq Proof Assistant  /  The Coq Development Team     *)
(* <O___,, *   INRIA - CNRS - LIX - LRI - PPS - Copyright 1999-2010     *)
(*   \VV/  **************************************************************)
(*    //   *      This file is distributed under the terms of the       *)
(*         *       GNU Lesser General Public License Version 2.1        *)
(************************************************************************)

(* cr�er un Makefile pour un d�veloppement Coq automatiquement *)

type target =
  | ML of string (* ML file : foo.ml -> (ML "foo.ml") *)
  | MLI of string (* MLI file : foo.mli -> (MLI "foo.mli") *)
  | ML4 of string (* ML4 file : foo.ml4 -> (ML4 "foo.ml4") *)
  | V of string  (* V file : foo.v -> (V "foo") *)
  | Special of string * string * string (* file, dependencies, command *)
  | Subdir of string
  | Def of string * string (* X=foo -> Def ("X","foo") *)
  | Include of string
  | RInclude of string * string (* -R physicalpath logicalpath *)

let output_channel = ref stdout
let makefile_name = ref "Makefile"
let make_name = ref ""

let some_vfile = ref false
let some_mlfile = ref false
let some_mlifile = ref false
let some_ml4file = ref false

let opt = ref "-opt"
let impredicative_set = ref false
let no_install = ref false

let print x = output_string !output_channel x
let printf x = Printf.fprintf !output_channel x

let rec print_list sep = function
  | [ x ] -> print x
  | x :: l -> print x; print sep; print_list sep l
  | [] -> ()

let list_iter_i f =
  let rec aux i = function [] -> () | a::l -> f i a; aux (i+1) l in aux 1

let section s =
  let l = String.length s in
  let sep = String.make (l+5) '#'
  and sep2 = String.make (l+5) ' ' in
  String.set sep (l+4) '\n';
  String.set sep2 0 '#';
  String.set sep2 (l+3) '#';
  String.set sep2 (l+4) '\n';
  print sep;
  print sep2;
  print "# "; print s; print " #\n";
  print sep2;
  print sep;
  print "\n"

let usage () =
  output_string stderr "Usage summary:

coq_makefile [subdirectory] .... [file.v] ... [file.ml[i4]?] ... [-custom
  command dependencies file] ... [-I dir] ... [-R physicalpath logicalpath]
  ... [VARIABLE = value] ...  [-opt|-byte] [-impredicative-set] [-no-install]
  [-f file] [-o file] [-h] [--help]

[file.v]: Coq file to be compiled
[file.ml[i4]?]: Objective Caml file to be compiled
[subdirectory] : subdirectory that should be \"made\"
[-custom command dependencies file]: add target \"file\" with command
  \"command\" and dependencies \"dependencies\"
[-I dir]: look for dependencies in \"dir\"
[-R physicalpath logicalpath]: look for dependencies resursively starting from
 \"physicalpath\". The logical path associated to the physical path is
 \"logicalpath\".
[VARIABLE = value]: Add the variable definition \"VARIABLE=value\"
[-byte]: compile with byte-code version of coq
[-opt]: compile with native-code version of coq
[-impredicative-set]: compile with option -impredicative-set of coq
[-no-install]: build a makefile with no install target
[-f file]: take the contents of file as arguments
[-o file]: output should go in file file
[-h]: print this usage summary
[--help]: equivalent to [-h]\n";
  exit 1

let is_genrule r =
    let genrule = Str.regexp("%") in
      Str.string_match genrule r 0

let absolute_dir dir =
  let current = Sys.getcwd () in
    Sys.chdir dir;
    let dir' = Sys.getcwd () in
      Sys.chdir current;
      dir'

let is_prefix dir1 dir2 =
  let l1 = String.length dir1 in
  let l2 = String.length dir2 in
    dir1 = dir2 or (l1 < l2 & String.sub dir2 0 l1 = dir1 & dir2.[l1] = '/')

let canonize f =
  let l = String.length f in
  if l > 2 && f.[0] = '.' && f.[1] = '/' then
    let n = let i = ref 2 in while !i < l && f.[!i] = '/' do incr i done; !i in
    String.sub f n (l-n)
  else f

let is_absolute_prefix dir dir' =
  is_prefix (absolute_dir dir) (absolute_dir dir')

let is_included dir = function
  | RInclude (dir',_) -> is_absolute_prefix dir' dir
  | Include dir' -> absolute_dir dir = absolute_dir dir'
  | _ -> false

let has_top_file = function
  | ML s | V s | MLI s | ML4 s -> s = Filename.basename s
  | _ -> false

let physical_dir_of_logical_dir ldir =
  let pdir = String.copy ldir in
  for i = 0 to String.length ldir - 1 do
    if pdir.[i] = '.' then pdir.[i] <- '/';
  done;
  pdir

let standard ()=
  print "byte:\n";
  print "\t$(MAKE) all \"OPT:=-byte\"\n\n";
  print "opt:\n";
  if !opt = "" then print "\t@echo \"WARNING: opt is disabled\"\n";
  print "\t$(MAKE) all \"OPT:="; print !opt; print "\"\n\n"

let is_prefix_of_file dir f =
  is_prefix dir (absolute_dir (Filename.dirname f))

let classify_files_by_root var files (inc_i,inc_r) =
  if not (List.exists (fun (pdir,_,_) -> pdir = ".") inc_r) then
    begin
      (* Files in the scope of a -R option (assuming they are disjoint) *)
      list_iter_i (fun i (pdir,ldir,abspdir) ->
	if List.exists (is_prefix_of_file abspdir) files then
	  printf "%s%d:=$(patsubst %s/%%,%%,$(filter %s/%%,$(%s)))\n"
	    var i pdir pdir var)
	inc_r;
      (* Files not in the scope of a -R option *)
      let pat_of_dir (pdir,_,_) = pdir^"/%" in
      let pdir_patterns = String.concat " " (List.map pat_of_dir inc_r) in
      printf "%s0:=$(filter-out %s,$(%s))\n" var pdir_patterns var
    end

let install_include_by_root path_var files_var files (_,inc_r) =
  try
    (* All files caught by a -R . option (assuming it is the only one) *)
    let ldir = match inc_r with
      |[(".",t,_)] -> t
      |l -> let out = List.assoc "." (List.map (fun (p,l,_) -> (p,l)) inc_r) in
	 let () = prerr_string "Warning: install rule assumes that -R . _ is the only -R option" in
	   out in
    let pdir = physical_dir_of_logical_dir ldir in
    printf "\tfor i in $(%s); do \\\n" files_var;
    printf "\t install -d `dirname $(DSTROOT)$(%s)user-contrib/%s/$$i`; \\\n\t install $$i $(DSTROOT)$(%s)user-contrib/%s/$$i; \\\n" path_var pdir path_var pdir;
    printf "\tdone\n"
  with Not_found ->
    (* Files in the scope of a -R option (assuming they are disjoint) *)
    list_iter_i (fun i (pdir,ldir,abspdir) ->
      if List.exists (is_prefix_of_file abspdir) files then
	begin
	  let pdir' = physical_dir_of_logical_dir ldir in
	  printf "\tcd %s; for i in $(%s%d); do \\\n" pdir files_var i;
	  printf "\t install -d `dirname $(DSTROOT)$(%s)user-contrib/%s/$$i`; \\\n\t install $$i $(DSTROOT)$(%s)user-contrib/%s/$$i; \\\n" path_var pdir' path_var pdir';
	  printf "\tdone\n"
	end) inc_r;
    (* Files not in the scope of a -R option *)
    printf "\tfor i in $(%s0); do \\\n" files_var;
    printf "\t install -d `dirname $(DSTROOT)$(%s)user-contrib/$(INSTALLDEFAULTROOT)/$$i`; \\\n\t install $$i $(DSTROOT)$(%s)user-contrib/$(INSTALLDEFAULTROOT)/$$i; \\\n" path_var path_var;
    printf "\tdone\n"

let string_prefix a b =
  let rec aux i = try if a.[i] = b.[i] then aux (i+1) else i with |Invalid_argument _ -> i in
    String.sub a 0 (aux 0)

let install_doc some_vfiles some_mlifiles (_,inc_r) =
  let install_one_kind kind dir =
    printf "\tinstall -d $(DSTROOT)$(DOCDIR)user-contrib/%s/%s\n" dir kind;
    printf "\tfor i in %s/*; do \\\n" kind;
    printf "\t install $$i $(DSTROOT)$(DOCDIR)user-contrib/%s/$$i;\\\n" dir;
    print "\tdone\n" in
    print "install-doc:\n";
    let () = match inc_r with
      |[] ->
	 if some_vfiles then install_one_kind "html" "$(INSTALLDEFAULTROOT)";
	  if some_mlifiles then install_one_kind "mlihtml" "$(INSTALLDEFAULTROOT)";
      |(_,lp,_)::q ->
	 let pr = List.fold_left (fun a (_,b,_) -> string_prefix a b) lp q in
	   if (pr <> "") && ((lp = pr) || pr.[String.length pr - 1] = '.') then begin
	     let rt = physical_dir_of_logical_dir pr in
	       if some_vfiles then install_one_kind "html" rt;
	       if some_mlifiles then install_one_kind "mlihtml" rt;
	   end else begin
	     prerr_string "Warning: -R options don't have a correct common preffix,
 install-doc will put anything in $INSTALLDEFAULTROOT";
	   if some_vfiles then install_one_kind "html" "$(INSTALLDEFAULTROOT)";
	   if some_mlifiles then install_one_kind "mlihtml" "$(INSTALLDEFAULTROOT)";
	   end in
      print "\n"

let install (vfiles,(mlifiles,ml4files,mlfiles),_,sds) inc =
  let not_empty = function |[] -> false |_::_ -> true in
  let cmfiles = mlfiles@ml4files in
    if (not_empty cmfiles) then begin
      print "install-natdynlink:\n";
      install_include_by_root "COQLIB" "CMXSFILES" cmfiles inc;
      print "\n";
    end;
    print "install:";
    if (not_empty cmfiles) then print "$(if ifeq '$(HASNATDYNLINK)' 'true',install-natdynlink)";
    print "\n";
    if not_empty vfiles then install_include_by_root "COQLIB" "VOFILES" vfiles inc;
    if (not_empty cmfiles) then begin
      install_include_by_root "COQLIB" "CMOFILES" cmfiles inc;
      install_include_by_root "COQLIB" "CMIFILES" cmfiles inc;
    end;
    List.iter
      (fun x ->
	 printf "\t(cd %s; $(MAKE) DSTROOT=$(DSTROOT) INSTALLDEFAULTROOT=$(INSTALLDEFAULTROOT)/%s install)\n" x x)
      sds;
    print "\n";
    install_doc (not_empty vfiles) (not_empty mlifiles) inc

let make_makefile sds =
  if !make_name <> "" then begin
    printf "%s: %s\n" !makefile_name !make_name;
    print "\tmv -f $@ $@.bak\n";
    print "\t$(COQBIN)coq_makefile -f $< -o $@\n\n";
    List.iter
      (fun x -> print "\t(cd "; print x; print " ; $(MAKE) Makefile)\n")
      sds;
    print "\n";
  end

let clean sds sps =
  print "clean:\n";
  print "\trm -f *~ Makefile-localvars.gen\n";
  if !some_mlfile || !some_mlifile || !some_ml4file then
    print "\trm -f $(CMOFILES) $(CMIFILES) $(CMXFILES) $(CMXSFILES) $(OFILES) $(MLFILES:.ml=.ml.d) $(MLIFILES:.mli=.mli.d) $(ML4FILES:.ml4=.ml4.d)\n";
  if !some_vfile then
    print "\trm -f $(VOFILES) $(VIFILES) $(GFILES) $(VFILES:.v=.v.d)\n";
  print "\trm -f all.ps all-gal.ps all.pdf all-gal.pdf all.glob $(VFILES:.v=.glob) $(VFILES:.v=.tex) $(VFILES:.v=.g.tex) all-mli.tex\n";
  print "\t- rm -rf html mlihtml\n";
  List.iter
    (fun (file,_,_) ->
       if not (is_genrule file) then
	 (print "\t- rm -rf "; print file; print "\n"))
    sps;
  List.iter
    (fun x -> print "\t(cd "; print x; print " ; $(MAKE) clean)\n")
    sds;
  print "\n";
  print "archclean:\n";
  print "\trm -f *.cmx *.o\n";
  List.iter
    (fun x -> print "\t(cd "; print x; print " ; $(MAKE) archclean)\n")
    sds;
  print "\n\n";
  print "printenv: Makefile-localvars.gen\n\t@cat $^\n";
  print "\t@echo CAMLC =\t$(CAMLC)\n\t@echo CAMLOPTC =\t$(CAMLOPTC)\n\t@echo PP =\t$(PP)\n\t@echo COQFLAGS =\t$(COQFLAGS)\n\n"

let header_includes () = ()

let footer_includes () =
  if !some_vfile then print "-include $(VFILES:.v=.v.d)\n.SECONDARY: $(VFILES:.v=.v.d)\n\n";
  if !some_mlfile then print "-include $(MLFILES:.ml=.ml.d)\n.SECONDARY: $(MLFILES:.ml=.ml.d)\n\n";
  if !some_mlifile then print "-include $(MLIFILES:.mli=.mli.d)\n.SECONDARY: $(MLIFILES:.mli=.mli.d)\n\n";
  if !some_ml4file then print "-include $(ML4FILES:.ml4=.ml4.d)\n.SECONDARY: $(ML4FILES:.ml4=.ml4.d)\n\n"

let implicit () =
  let mli_rules () =
    print "%.cmi: %.mli\n\t$(CAMLC) $(ZDEBUG) $(ZFLAGS) $<\n\n";
    print "%.mli.d: %.mli\n";
    print "\t$(OCAMLDEP) -slash $(OCAMLLIBS) \"$<\" > \"$@\" || ( RV=$$?; rm -f \"$@\"; exit $${RV} )\n\n" in
  let ml4_rules () =
    print "%.cmo: %.ml4\n\t$(CAMLC) $(ZDEBUG) $(ZFLAGS) $(PP) -impl $<\n\n";
    print "%.cmx: %.ml4\n\t$(CAMLOPTC) $(ZDEBUG) $(ZFLAGS) $(PP) -impl $<\n\n";
    print "%.cmxs: %.ml4\n\t$(CAMLOPTLINK) $(ZDEBUG) $(ZFLAGS) -shared -o $@ $(PP) -impl $<\n\n";
    print "%.ml4.d: %.ml4\n";
    print "\t$(OCAMLDEP) -slash $(OCAMLLIBS) $(PP) -impl \"$<\" > \"$@\" || ( RV=$$?; rm -f \"$@\"; exit $${RV} )\n\n"in
  let ml_rules () =
    print "%.cmo: %.ml\n\t$(CAMLC) $(ZDEBUG) $(ZFLAGS) $<\n\n";
    print "%.cmx: %.ml\n\t$(CAMLOPTC) $(ZDEBUG) $(ZFLAGS) $<\n\n";
    print "%.cmxs: %.ml\n\t$(CAMLOPTLINK) $(ZDEBUG) $(ZFLAGS) -shared -o $@ $<\n\n";
    print "%.ml.d: %.ml\n";
    print "\t$(OCAMLDEP) -slash $(OCAMLLIBS) \"$<\" > \"$@\" || ( RV=$$?; rm -f \"$@\"; exit $${RV} )\n\n"
  and v_rule () =
    print "%.vo %.glob: %.v\n\t$(COQC) $(COQDEBUG) $(COQFLAGS) $*\n\n";
    print "%.vi: %.v\n\t$(COQC) -i $(COQDEBUG) $(COQFLAGS) $*\n\n";
    print "%.g: %.v\n\t$(GALLINA) $<\n\n";
    print "%.tex: %.v\n\t$(COQDOC) -latex $< -o $@\n\n";
    print "%.html: %.v %.glob\n\t$(COQDOC) -html $< -o $@\n\n";
    print "%.g.tex: %.v\n\t$(COQDOC) -latex -g $< -o $@\n\n";
    print "%.g.html: %.v %.glob\n\t$(COQDOC) -html -g $< -o $@\n\n";
    print "%.v.d: %.v\n";
    print "\t$(COQDEP) -slash $(COQLIBS) \"$<\" > \"$@\" || ( RV=$$?; rm -f \"$@\"; exit $${RV} )\n\n"
  in
    if !some_mlifile then mli_rules ();
    if !some_ml4file then ml4_rules ();
    if !some_mlfile then ml_rules ();
    if !some_vfile then v_rule ()

let variables defs =
  let var_aux (v,def) = print v; print "="; print def; print "\n" in
    section "Variables definitions.";
    List.iter var_aux defs;
    print "\n";
    print "ZFLAGS=$(OCAMLLIBS) $(COQSRCLIBS) -I $(CAMLP4LIB)\n";
    if !opt = "-byte" then
      print "override OPT:=-byte\n"
    else
      print "OPT?=\n";
    if !impredicative_set = true then print "OTHERFLAGS=-impredicative-set\n";
    (* Coq executables and relative variables *)
    print "COQFLAGS?=-q $(OPT) $(COQLIBS) $(OTHERFLAGS) $(COQ_XML)\n";
    print "COQC?=$(COQBIN)coqc\n";
    print "COQDEP?=$(COQBIN)coqdep -c\n";
    print "GALLINA?=$(COQBIN)gallina\n";
    print "COQDOC?=$(COQBIN)coqdoc\n";
    (* Caml executables and relative variables *)
    print "CAMLC?=$(OCAMLC) -c -rectypes\n";
    print "CAMLOPTC?=$(OCAMLOPT) -c -rectypes\n";
    print "CAMLLINK?=$(OCAMLC) -rectypes\n";
    print "CAMLOPTLINK?=$(OCAMLOPT) -rectypes\n";

    print "GRAMMARS?=grammar.cma\n";
    print "CAMLP4EXTEND?=pa_extend.cmo pa_macro.cmo q_MLast.cmo\n";
    print "CAMLP4OPTIONS?=\n";
    print "PP?=-pp \"$(CAMLP4BIN)$(CAMLP4)o -I $(CAMLLIB) -I . $(COQSRCLIBS) $(CAMLP4EXTEND) $(GRAMMARS) $(CAMLP4OPTIONS) -impl\"\n";
    print "\n"

let parameters () =
  print "NOARG: all\n\n# \n";
  print "# This Makefile may take COQBIN as argument passed as environment variables:\n";
  print "#  to specify the directory where Coq binaries resides;\n";
  print "Makefile-localvars.gen:\n\t$(COQBIN)coqtop -config > $@\n\n";
  print "-include Makefile-localvars.gen\n.SECONDARY: Makefile-localvars.gen\n\n"

let include_dirs (inc_i,inc_r) =
  let parse_includes l = List.map (fun (x,_) -> "-I " ^ x) l in
  let parse_rec_includes l =
    List.map (fun (p,l,_) ->
      let l' = if l = "" then "\"\"" else l in "-R " ^ p ^ " " ^ l')
      l in
  let inc_i' = List.filter (fun (i,_) -> not (List.exists (fun (i',_,_) -> is_absolute_prefix i' i) inc_r)) inc_i in
  let str_i = parse_includes inc_i in
  let str_i' = parse_includes inc_i' in
  let str_r = parse_rec_includes inc_r in
    section "Libraries definitions.";
    print "OCAMLLIBS?="; print_list "\\\n  " str_i; print "\n";
    print "COQSRCLIBS?=-I $(COQLIB)kernel -I $(COQLIB)lib \\
  -I $(COQLIB)library -I $(COQLIB)parsing \\
  -I $(COQLIB)pretyping -I $(COQLIB)interp \\
  -I $(COQLIB)proofs -I $(COQLIB)tactics \\
  -I $(COQLIB)toplevel";
    List.iter (fun c -> print " \\
  -I $(COQLIB)plugins/"; print c) Coq_config.plugins_dirs; print "\n";
    print "COQLIBS?="; print_list "\\\n  " str_i'; print " "; print_list "\\\n  " str_r; print "\n";
    print "COQDOCLIBS?=";   print_list "\\\n  " str_r; print "\n\n"


let rec special = function
  | [] -> []
  | Special (file,deps,com) :: r -> (file,deps,com) :: (special r)
  | _ :: r -> special r

let custom sps =
  let pr_path (file,dependencies,com) =
    print file; print ": "; print dependencies; print "\n";
    print "\t"; print com; print "\n\n"
  in
    if sps <> [] then section "Custom targets.";
    List.iter pr_path sps

let subdirs sds =
  let pr_subdir s =
    print s; print ":\n\tcd "; print s; print " ; $(MAKE) all\n\n"
  in
    if sds <> [] then section "Subdirectories.";
    List.iter pr_subdir sds;
    section "Special targets.";
    print ".PHONY: ";
    print_list " "
      ("NOARG" :: "all" ::  "opt" :: "byte" :: "archclean" :: "clean" :: "install"
	:: "depend" :: "html" :: sds);
    print "\n\n"

let rec split_arguments = function
  | V n :: r ->
      let (v,m,o,s),i,d = split_arguments r in ((canonize n::v,m,o,s),i,d)
  | ML n :: r ->
      let (v,(mli,ml4,ml),o,s),i,d = split_arguments r in ((v,(mli,ml4,canonize n::ml),o,s),i,d)
  | MLI n :: r ->
      let (v,(mli,ml4,ml),o,s),i,d = split_arguments r in ((v,(canonize n::mli,ml4,ml),o,s),i,d)
  | ML4 n :: r ->
      let (v,(mli,ml4,ml),o,s),i,d = split_arguments r in ((v,(mli,canonize n::ml4,ml),o,s),i,d)
  | Special (n,dep,c) :: r ->
      let (v,m,o,s),i,d = split_arguments r in ((v,m,(n,dep,c)::o,s),i,d)
  | Subdir n :: r ->
      let (v,m,o,s),i,d = split_arguments r in ((v,m,o,n::s),i,d)
  | Include p :: r ->
      let t,(i,r),d = split_arguments r in (t,((p,absolute_dir p)::i,r),d)
  | RInclude (p,l) :: r ->
      let t,(i,r),d = split_arguments r in (t,(i,(p,l,absolute_dir p)::r),d)
  | Def (v,def) :: r ->
      let t,i,d = split_arguments r in (t,i,(v,def)::d)
  | [] -> ([],([],[],[]),[],[]),([],[]),[]

let main_targets vfiles (mlifiles,ml4files,mlfiles) other_targets inc =
  begin match vfiles with
    |[] -> ()
    |l ->
      print "VFILES:="; print_list "\\\n  " l; print "\n";
      print "VOFILES:=$(VFILES:.v=.vo)\n";
      classify_files_by_root "VOFILES" l inc;
      print "GLOBFILES:=$(VFILES:.v=.glob)\n";
      print "VIFILES:=$(VFILES:.v=.vi)\n";
      print "GFILES:=$(VFILES:.v=.g)\n";
      print "HTMLFILES:=$(VFILES:.v=.html)\n";
      print "GHTMLFILES:=$(VFILES:.v=.g.html)\n"
  end;
  begin match match ml4files,mlfiles with
    |[],[] -> []
    |[],ml ->
      print "MLFILES:="; print_list "\\\n  " ml; print "\n";
      print "CMOFILES:=$(MLFILES:.ml=.cmo)\n";
      ml
    |ml4,[] ->
      print "ML4FILES:="; print_list "\\\n  " ml4; print "\n";
      print "CMOFILES:=$(ML4FILES:.ml4=.cmo)\n";
      ml4
    |ml4,ml ->
      print "ML4FILES:="; print_list "\\\n  " ml4; print "\n";
      print "MLFILES:="; print_list "\\\n  " ml; print "\n";
      print "CMOFILES:=$(ML4FILES:.ml4=.cmo) $(MLFILES:.ml=.cmo)\n";
      ml@ml4
  with
    |[] -> ()
    |l ->
      classify_files_by_root "CMOFILES" l inc;
      print "CMIFILES:=$(sort $(CMOFILES:.cmo=.cmi) $(MLIFILES:.mli=.cmi))\n";
      classify_files_by_root "CMIFILES" l inc;
      print "CMXFILES:=$(CMOFILES:.cmo=.cmx)\n";
      print "CMXSFILES:=$(CMXFILES:.cmx=.cmxs)\n";
      classify_files_by_root "CMXSFILES" l inc;
      print "OFILES:=$(CMXFILES:.cmx=.o)\n";
  end;
  begin match mlifiles with
    |[] -> ()
    |l ->
      print "MLIFILES:="; print_list "\\\n  " l; print "\n";
  end;
  print "\nall: ";
  if !some_vfile then print "$(VOFILES) ";
  if !some_mlfile || !some_ml4file then begin
    print "$(CMOFILES) ";
    print "$(if ifeq '$(HASNATDYNLINK)' 'true',$(CMXSFILES)) ";
  end;
  print_list "\\\n  " other_targets; print "\n\n";
  if !some_mlifile then
    begin
      print "mlihtml: $(MLIFILES:.mli=.cmi)\n";
      print "\t mkdir $@ || rm -rf $@/*\n";
      print "\t$(OCAMLDOC) -html -rectypes -d $@ -m A $(ZDEBUG) $(ZFLAGS) $(^:.cmi=.mli)\n\n";
      print "all-mli.tex: $(MLIFILES:.mli=.cmi)\n";
      print "\t$(OCAMLDOC) -latex -rectypes -o $@ -m A $(ZDEBUG) $(ZFLAGS) $(^:.cmi=.mli)\n\n";
    end;
  if !some_vfile then
    begin
      print "spec: $(VIFILES)\n\n";
      print "gallina: $(GFILES)\n\n";
      print "html: $(GLOBFILES) $(VFILES)\n";
      print "\t- mkdir -p html\n";
      print "\t$(COQDOC) -toc -html $(COQDOCLIBS) -d html $(VFILES)\n\n";
      print "gallinahtml: $(GLOBFILES) $(VFILES)\n";
      print "\t- mkdir -p html\n";
      print "\t$(COQDOC) -toc -html -g $(COQDOCLIBS) -d html $(VFILES)\n\n";
      print "all.ps: $(VFILES)\n";
      print "\t$(COQDOC) -toc -ps $(COQDOCLIBS) -o $@ `$(COQDEP) -sort -suffix .v $(VFILES)`\n\n";
      print "all-gal.ps: $(VFILES)\n";
      print "\t$(COQDOC) -toc -ps -g $(COQDOCLIBS) -o $@ `$(COQDEP) -sort -suffix .v $(VFILES)`\n\n";
      print "all.pdf: $(VFILES)\n";
      print "\t$(COQDOC) -toc -pdf $(COQDOCLIBS) -o $@ `$(COQDEP) -sort -suffix .v $(VFILES)`\n\n";
      print "all-gal.pdf: $(VFILES)\n";
      print "\t$(COQDOC) -toc -pdf -g $(COQDOCLIBS) -o $@ `$(COQDEP) -sort -suffix .v $(VFILES)`\n\n";
      print "\n"
    end

let all_target (vfiles, mlfiles, sps, sds) inc =
  let special_targets = List.filter (fun (n,_,_) -> not (is_genrule n)) sps in
  let other_targets = List.map (function x,_,_ -> x) special_targets @ sds in
  section "Definition of the \"all\" target.";
  main_targets vfiles mlfiles other_targets inc;
  custom sps;
  subdirs sds

let parse f =
  let rec string = parser
    | [< '' ' | '\n' | '\t' >] -> ""
    | [< 'c; s >] -> (String.make 1 c)^(string s)
    | [< >] -> ""
  and string2 = parser
    | [< ''"' >] -> ""
    | [< 'c; s >] -> (String.make 1 c)^(string2 s)
  and skip_comment = parser
    | [< ''\n'; s >] -> s
    | [< 'c; s >] -> skip_comment s
    | [< >] -> [< >]
  and args = parser
    | [< '' ' | '\n' | '\t'; s >] -> args s
    | [< ''#'; s >] -> args (skip_comment s)
    | [< ''"'; str = string2; s >] -> ("" ^ str) :: args s
    | [< 'c; str = string; s >] -> ((String.make 1 c) ^ str) :: (args s)
    | [< >] -> []
  in
  let c = open_in f in
  let res = args (Stream.of_channel c) in
    close_in c;
    res

let rec process_cmd_line = function
  | [] -> []
  | ("-h"|"--help") :: _ ->
      usage ()
  | ("-no-opt"|"-byte") :: r ->
      opt := "-byte"; process_cmd_line r
  | ("-full"|"-opt") :: r ->
      opt := "-opt"; process_cmd_line r
  | "-impredicative-set" :: r ->
      impredicative_set := true; process_cmd_line r
  | "-no-install" :: r ->
      no_install := true; process_cmd_line r
  | "-custom" :: com :: dependencies :: file :: r ->
      let check_dep f =
	if Filename.check_suffix f ".v" then
          some_vfile := true
	else if (Filename.check_suffix f ".ml") || (Filename.check_suffix f ".ml4") then
          some_mlfile := true
      in
	List.iter check_dep (Str.split (Str.regexp "[ \t]+") dependencies);
	Special (file,dependencies,com) :: (process_cmd_line r)
  | "-I" :: d :: r ->
      Include d :: (process_cmd_line r)
  | "-R" :: p :: l :: r ->
      RInclude (p,l) :: (process_cmd_line r)
  | ("-I"|"-custom") :: _ ->
      usage ()
  | "-f" :: file :: r ->
      make_name := file;
      process_cmd_line ((parse file)@r)
  | ["-f"] ->
      usage ()
  | "-o" :: file :: r ->
      makefile_name := file;
      output_channel := (open_out file);
      (process_cmd_line r)
  | v :: "=" :: def :: r ->
      Def (v,def) :: (process_cmd_line r)
  | f :: r ->
    if Filename.check_suffix f ".v" then begin
      some_vfile := true;
      V f :: (process_cmd_line r)
    end else if (Filename.check_suffix f ".ml") then begin
      some_mlfile := true;
      ML f :: (process_cmd_line r)
    end else if (Filename.check_suffix f ".ml4") then begin
      some_ml4file := true;
      ML4 f :: (process_cmd_line r)
    end else if (Filename.check_suffix f ".mli") then begin
      some_mlifile := true;
      MLI f :: (process_cmd_line r)
    end else
          Subdir f :: (process_cmd_line r)

let banner () =
  print (Printf.sprintf
"#############################################################################
##  v      #                   The Coq Proof Assistant                     ##
## <O___,, #                INRIA - CNRS - LIX - LRI - PPS                 ##
##   \\VV/  #                                                               ##
##    //   #  Makefile automagically generated by coq_makefile V%s ##
#############################################################################

" (Coq_config.version ^ String.make (10 - String.length Coq_config.version) ' '))

let warning () =
  print "# WARNING\n#\n";
  print "# This Makefile has been automagically generated\n";
  print "# Edit at your own risks !\n";
  print "#\n# END OF WARNING\n\n"

let print_list l = List.iter (fun x -> print x; print " ") l

let command_line args =
  print "#\n# This Makefile was generated by the command line :\n";
  print "# coq_makefile ";
  print_list args;
  print "\n#\n\n"

let directories_deps l =
  let print_dep f dep =
    if dep <> [] then begin print f; print ": "; print_list dep; print "\n" end
  in
  let rec iter ((dirs,before) as acc) = function
    | [] ->
	()
    | (Subdir d) :: l ->
	print_dep d before; iter (d :: dirs, d :: before) l
    | (ML f) :: l | (V f) :: l | (MLI f) :: l | (ML4 f) :: l ->
	print_dep f dirs; iter (dirs, f :: before) l
    | (Special (f,_,_)) :: l ->
	print_dep f dirs; iter (dirs, f :: before) l
    | _ :: l ->
	iter acc l
  in
    iter ([],[]) l

let ensure_root_dir l =
  if List.exists (is_included ".") l or not (List.exists has_top_file l) then
    l
  else
    Include "." :: l

let warn_install_at_root_directory (vfiles,(mlifiles,ml4files,mlfiles),_,_) (inc_i,inc_r) =
  let inc_r_top = List.filter (fun (_,ldir,_) -> ldir = "") inc_r in
  let inc_top = List.map (fun (p,_,_) -> p) inc_r_top @ List.map fst inc_i in
  let files = vfiles @ mlifiles @ ml4files @ mlfiles in
  if not !no_install &&
    List.exists (fun f -> List.mem (Filename.dirname f) inc_top) files
  then
    Printf.eprintf "Warning: install target will copy files at the first level of the coq contributions installation directory; option -R %sis recommended\n"
      (if inc_r_top = [] then "" else "with non trivial logical root ")

let check_overlapping_include (_,inc_r) =
  let pwd = Sys.getcwd () in
  let rec aux = function
    | [] -> ()
    | (pdir,_,abspdir)::l ->
	if not (is_prefix pwd abspdir) then
	  Printf.eprintf "Warning: in option -R, %s is not a subdirectory of the current directory\n" pdir;
	List.iter (fun (pdir',_,abspdir') ->
	  if is_prefix abspdir abspdir' or is_prefix abspdir' abspdir then
	    Printf.eprintf "Warning: in options -R, %s and %s overlap\n" pdir pdir') l;
  in aux inc_r

let do_makefile args =
  let l = process_cmd_line args in
  let l = ensure_root_dir l in
  let (_,_,sps,sds as targets), inc, defs = split_arguments l in
  warn_install_at_root_directory targets inc;
  check_overlapping_include inc;
  banner ();
  header_includes ();
  warning ();
  command_line args;
  parameters ();
  include_dirs inc;
  variables defs;
  all_target targets inc;
  implicit ();
  standard ();
  if not !no_install then install targets inc;
  clean sds sps;
  make_makefile sds;
  (* TEST directories_deps l; *)
  footer_includes ();
  warning ();
  if not (!output_channel == stdout) then close_out !output_channel;
  exit 0

let main () =
  let args =
    if Array.length Sys.argv = 1 then usage ();
    List.tl (Array.to_list Sys.argv)
  in
    do_makefile args

let _ = Printexc.catch main ()
