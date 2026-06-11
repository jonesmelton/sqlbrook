type result =
  { output : string
  ; had_passthrough : bool
  }

val format : string -> result
