Template ← {
  0=+´'|'=𝕩?𝕩;
  parts ← +`'|'=𝕩
  "unclosed template"!0=2|⌈´parts
  back ← 1↓𝕩/˜2≤parts
  front ← 𝕩/˜0=parts
  var ← 1↓𝕩/˜1=parts
  concrete ← •FChars var∾".bar"
  2<⌈´parts?front∾concrete∾𝕊back;
  parts ← +`'|'=𝕩
  back ← 1↓𝕩/˜2≤parts
  front ← 𝕩/˜0=parts
  var ← 1↓𝕩/˜1=parts
  concrete ← •FChars var∾".bar"
  front∾concrete∾back
}
"too many or too less args"!1=≠•args
lines ← •FLines ⊑•args
ress ← Template¨lines
•Out¨ress
