open QCheck
open Quasifind
open Ast.Typed

(* Property 1: Size comparison logic consistency *)
(* If we have a SizeGt(n) rule, any file with size > n must evaluate to True *)
let prop_size_gt =
  Test.make ~count:1000 ~name:"prop_size_gt"
    (pair nat_small nat_small) (* (threshold, actual_size) *)
    (fun (threshold_int, actual_int) ->
       let threshold = Int64.of_int threshold_int in
       let size = Int64.of_int actual_int in
       let expr = Size (SizeGt threshold) in
       let entry = {
         Eval.name = "test";
         path = "test";
         kind = Ast.File;
         size = size;
         mtime = 0.0;
         perm = 0
       } in
       let result = Eval.eval 0.0 expr entry in
       if size > threshold then result else not result
    )

(* Property 2: Time comparison logic consistency *)
(* TimeLt(n) means file age < n. Age = now - mtime. *)
(* If we set now=100.0, mtime=90.0 (age=10.0), checking age < 20.0 should be true *)
let prop_time_lt =
  Test.make ~count:1000 ~name:"prop_time_lt"
    (triple nat_small nat_small nat_small) (* (now, age_threshold, actual_age) *)
    (fun (now_int, threshold_int, age_int) ->
       let now = float_of_int now_int in
       let threshold = float_of_int threshold_int in
       let age = float_of_int age_int in
       
       let mtime = now -. age in
       let expr = MTime (TimeLt threshold) in
       let entry = {
         Eval.name = "test";
         path = "test";
         kind = Ast.File;
         size = 0L;
         mtime = mtime;
         perm = 0
       } in
       let result = Eval.eval now expr entry in
       if age < threshold then result else not result
    )

let () =
  QCheck_runner.run_tests_main [
    prop_size_gt;
    prop_time_lt;
  ]
