Template ← {
  parts ← +`'|'=𝕩
  front ← 𝕩/˜0=parts
  back ← 1↓𝕩/˜2≤parts
  var ← 1↓𝕩/˜1=parts
  # switch var into a concrete
  concrete ← "DATE"
  front∾concrete∾back
}
ex1 ← "dfvmfdvlfdkvmfdkldm|date|dfnfdlvmflkvm"
Template ex1
