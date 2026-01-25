(* Smith-Waterman Algorithm with Affine Gap Penalty for Fuzzy Matching *)

let score_match = 10
let score_mismatch = -1
let boundary_bonus = 5
let camel_bonus = 5
let gap_open_penalty = -3
let gap_extend_penalty = -1

let is_separator c =
  match c with
  | '/' | '_' | '-' | '.' | ' ' -> true
  | _ -> false

let is_upper c =
  c >= 'A' && c <= 'Z'

let is_subsequence ~query ~candidate =
  let m = String.length query in
  let n = String.length candidate in
  let rec aux i j =
    if i = m then true
    else if j = n then false
    else if Char.lowercase_ascii query.[i] = Char.lowercase_ascii candidate.[j] then
      aux (i + 1) (j + 1)
    else
      aux i (j + 1)
  in
  aux 0 0

let match_score ~query ~candidate =
  if String.length query = 0 then Some 0 else
  if not (is_subsequence ~query ~candidate) then None
  else
    let m = String.length query in
    let n = String.length candidate in
    (* 
       DP State:
       H[i][j]: Score of optimal alignment ending at Query[i-1] and Candidate[j-1].
       Usually SW allows 0 (local alignment reset), but for subsequence match we want to match WHOLE query.
       So we don't reset to 0. We behave more like Needleman-Wunsch but with "start at any char in candidate"?
       No, we want to match query[0]...query[m-1] to some subsequence of candidate.
       
       Let's use a simpler heuristic scoring often used in fuzzy finders if full SW is overkill.
       But I promised SW.
       
       DP[i][j] = Score of matching query[0..i] ending at candidate[j].
       Recurrence:
       if query[i] == candidate[j]:
         score = score_match + bonuses
         prev_score = max(DP[i-1][k] + gap_penalty(j-k)) for k < j
         DP[i][j] = prev_score + score
       else:
         DP[i][j] = -infinity (since we require matching characters for the subsequence)
         
       Optimization:
       We only need to iterate forward.
       For gap penalties, naive is O(N^3) or O(N^2 * M).
       With constant gap penalty ( affine: open + ext*len ), we can optimize tracking.
       
       For simplicity, let's just use:
       DP[i][j] = score match + max(
          DP[i-1][j-1] + contiguous_bonus,
          Max_k(DP[i-1][k]) + gap_penalty
       )
    *)
    
    let dp = Array.make_matrix m n min_int in
    
    (* Initialize first row *)
    for j = 0 to n - 1 do
      if Char.lowercase_ascii query.[0] = Char.lowercase_ascii candidate.[j] then
        let bonus = 
          if j = 0 then boundary_bonus
          else if is_separator candidate.[j-1] then boundary_bonus
          else if is_upper candidate.[j] && not (is_upper candidate.[j-1]) then camel_bonus
          else 0
        in
        dp.(0).(j) <- score_match + bonus
    done;
    
    (* Fill rest *)
    for i = 1 to m - 1 do
      (* Track max score from previous row to handle gaps efficiently *)
      (* We want max(dp[i-1][k] - gap_penalty_function(j, k)) *)
      (* Assuming simplistic gap penalty: -O - (j-k)*E *)
      (* max(dp[i-1][k] + k*E) - j*E - O *)
      let max_prev_gapped = ref min_int in
      
      for j = 1 to n - 1 do
         (* Update max_prev_gapped considering dp[i-1][j-1] *)
         (* When moving to j, the candidate k can be j-1. *)
         (* The term for k=j-1 is dp[i-1][j-1] + (j-1)*E *)
         let prev_val = dp.(i-1).(j-1) in
         if prev_val > min_int then (
            let val_with_pos = prev_val + (j-1) * gap_extend_penalty in
            if val_with_pos > !max_prev_gapped then max_prev_gapped := val_with_pos
         );
      
         if Char.lowercase_ascii query.[i] = Char.lowercase_ascii candidate.[j] then
            let bonus = 
              if is_separator candidate.[j-1] then boundary_bonus
              else if is_upper candidate.[j] && not (is_upper candidate.[j-1]) then camel_bonus
              else 0
            in
            
            (* 1. Contiguous from j-1 *)
            let score_contiguous = 
              if prev_val > min_int then prev_val + score_match + bonus + 2 (* context bonus *)
              else min_int
            in
            
            (* 2. Gapped from any k < j-1 (or j-1 if we treat it as gap, but better handled as contiguous) *)
            (* max_prev_gapped has max(dp[i-1][k] + k*E). 
               We simply subtract j*E + O *)
            let score_gapped =
              if !max_prev_gapped > min_int then
                 !max_prev_gapped - (j * gap_extend_penalty) + gap_open_penalty + score_match + bonus
              else min_int
            in
            
            dp.(i).(j) <- max score_contiguous score_gapped
      done
    done;
    
    (* Result is max of last row *)
    let max_score = ref min_int in
    for j = 0 to n - 1 do
      if dp.(m-1).(j) > !max_score then max_score := dp.(m-1).(j)
    done;
    
    if !max_score > min_int then Some !max_score else None

let rank ~query ~candidates =
  if query = "" then candidates else
  let scored = List.filter_map (fun s ->
    match match_score ~query ~candidate:s with
    | Some score -> Some (score, s)
    | None -> None
  ) candidates in
  
  List.sort (fun (s1, c1) (s2, c2) -> 
    if s1 <> s2 then compare s2 s1 (* Descending score *)
    else compare (String.length c1) (String.length c2) (* Prefer shorter match *)
  ) scored |> List.map snd
