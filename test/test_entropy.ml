open Alcotest
open Quasifind
open Ast
open Ast.Typed

let test_entropy_calc () =
  (* Low entropy: repeated characters *)
  let low = "AAAAAAAA" in
  (* High entropy: random-ish *)
  let high = "ABCDEFGH" in
  
  let calc = Eval.calculate_entropy in
  let e_low = calc low in
  let e_high = calc high in
  
  (* "AAAA..." -> p('A')=1.0, log(1)=0 => entropy 0.0 *)
  check (float 0.001) "low entropy is 0" 0.0 e_low;
  
  (* "ABC..." -> p(x)=1/8, log2(1/8)=-3, - sum(1/8 * -3) = 3.0 *)
  check (float 0.001) "high entropy is 3.0" 3.0 e_high

let test_eval_entropy () =
  let temp_file = Filename.temp_file "test_entropy" ".dat" in
  let oc = open_out temp_file in
  output_string oc "AAAAAAAA";
  close_out oc;
  
  let entry = { Eval.name = "test"; path = temp_file; kind = Ast.File; size = 8L; mtime = 0.0; perm = 0 } in
  
  (* Entropy == 0.0 *)
  let expr_eq = Entropy (FloatEq 0.0) in
  check bool "entropy eq 0.0" true (Eval.eval 0.0 expr_eq entry);
  
  let expr_gt = Entropy (FloatGt 1.0) in
  check bool "entropy gt 1.0 false" false (Eval.eval 0.0 expr_gt entry);
  
  Sys.remove temp_file

let suite = [
  "Entropy", [
    test_case "Calculation" `Quick test_entropy_calc;
    test_case "Evaluation" `Quick test_eval_entropy;
  ]
]

let () = run "Quasifind Entropy" suite
