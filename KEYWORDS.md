# Terraform Keywords & Concepts

A personal reference of every Terraform concept covered during building this module library,
plus essential functions for general Terraform DevOps work.
Each entry includes an explanation, a real example, and how to practice in the Terraform Console.

## How to use the Terraform Console

The Terraform Console is an interactive calculator for Terraform expressions.
Run it inside any directory after `terraform init`:

```bash
terraform console
```

You get a `>` prompt. Type any expression and press Enter to see the result.
Type `exit` or Ctrl+D to quit. **No real AWS resources are created** — it is read-only.

---

# SECTION A — Collection Functions

## 1. `toset()`

Converts a list into a set. Sets have no duplicates and no order.
Required because `for_each` only accepts `set(string)` or `map` — not lists.

```hcl
toset(["443", "80", "443"])   # duplicates removed → {"443", "80"}
toset([])                     # empty set → {}
```

**Practice in console:**
```
> toset(["443", "80", "443"])
toset(["443", "80"])

> toset([])
toset([])
```

---

## 2. `tostring()` and `tonumber()`

Convert between string and number types.
`for_each` needs string keys. AWS needs number ports. Convert between them.

```hcl
tostring(443)     # 443  →  "443"
tonumber("443")   # "443" →  443
```

**Practice in console:**
```
> tostring(443)
"443"

> tonumber("443")
443
```

---

## 3. `length()`

Returns the number of elements in a list, map, or characters in a string.
Very commonly used in `count` conditions and `validation` blocks.

```hcl
length([])                          # 0 — empty list
length(["a", "b", "c"])             # 3
length({"a" = 1, "b" = 2})         # 2 — number of map keys
length("hello")                     # 5 — number of characters

# Real use — only create IAM role if buckets are provided
count = length(var.s3_read_bucket_arns) > 0 ? 1 : 0
```

**Practice in console:**
```
> length(["a", "b", "c"])
3

> length({})
0

> length("eu-west-1")
9
```

---

## 4. `lookup()`

Safely reads a value from a map by key. Returns a default if the key does not exist.
Prevents errors when a key might be missing.

```hcl
lookup({"eu-west-1" = "ami-123", "us-east-1" = "ami-456"}, "eu-west-1", "ami-default")
# → "ami-123"

lookup({"eu-west-1" = "ami-123"}, "ap-southeast-1", "ami-default")
# → "ami-default"  (key missing, returns default)
```

**Practice in console:**
```
> lookup({"a" = "1", "b" = "2"}, "a", "not-found")
"1"

> lookup({"a" = "1", "b" = "2"}, "z", "not-found")
"not-found"
```

---

## 5. `keys()` and `values()`

Extract all keys or all values from a map as a list.

```hcl
keys({"eu-west-1a" = "10.0.0.0/24", "eu-west-1b" = "10.0.1.0/24"})
# → ["eu-west-1a", "eu-west-1b"]

values({"eu-west-1a" = "10.0.0.0/24", "eu-west-1b" = "10.0.1.0/24"})
# → ["10.0.0.0/24", "10.0.1.0/24"]
```

**Practice in console:**
```
> keys({"a" = "1", "b" = "2"})
["a", "b"]

> values({"a" = "1", "b" = "2"})
["1", "2"]
```

---

## 6. `zipmap()`

Combines two lists into a map — first list becomes keys, second becomes values.
Useful when you have parallel lists and need a map for `for_each`.

```hcl
zipmap(
  ["eu-west-1a", "eu-west-1b"],
  ["10.0.0.0/24", "10.0.1.0/24"]
)
# → {"eu-west-1a" = "10.0.0.0/24", "eu-west-1b" = "10.0.1.0/24"}
```

**Practice in console:**
```
> zipmap(["a", "b", "c"], ["1", "2", "3"])
{
  "a" = "1"
  "b" = "2"
  "c" = "3"
}
```

---

## 7. `flatten()`

Collapses a list of lists into a single flat list.
Used in IAM policies when combining multiple ARN lists.

```hcl
flatten([
  ["arn:aws:s3:::bucket-a", "arn:aws:s3:::bucket-b"],
  ["arn:aws:s3:::bucket-a/*", "arn:aws:s3:::bucket-b/*"]
])
# → ["arn:aws:s3:::bucket-a", "arn:aws:s3:::bucket-b",
#    "arn:aws:s3:::bucket-a/*", "arn:aws:s3:::bucket-b/*"]
```

**Practice in console:**
```
> flatten([["a", "b"], ["c", "d"]])
["a", "b", "c", "d"]

> flatten([["x"], [], ["y", "z"]])
["x", "y", "z"]
```

---

## 8. `concat()`

Joins two or more lists into one flat list. Unlike `flatten`, only works one level deep.
Used to combine a required list with an optional one.

```hcl
concat(["sg-0required"], ["sg-0extra1", "sg-0extra2"])
# → ["sg-0required", "sg-0extra1", "sg-0extra2"]

concat(["sg-0required"], [])   # → ["sg-0required"]
```

**Practice in console:**
```
> concat(["a", "b"], ["c", "d"])
["a", "b", "c", "d"]

> concat(["only"], [])
["only"]
```

---

## 9. `compact()`

Removes empty strings and null values from a list.
Useful when building lists from optional variables that might be null or empty.

```hcl
compact(["sg-0abc", null, "", "sg-0def"])
# → ["sg-0abc", "sg-0def"]
```

**Practice in console:**
```
> compact(["a", "", "b", null, "c"])
["a", "b", "c"]
```

---

## 10. `distinct()`

Removes duplicate values from a list, preserving order of first occurrence.

```hcl
distinct(["eu-west-1a", "eu-west-1b", "eu-west-1a"])
# → ["eu-west-1a", "eu-west-1b"]
```

**Practice in console:**
```
> distinct(["a", "b", "a", "c", "b"])
["a", "b", "c"]
```

---

## 11. `one()`

Returns the single element from a list of 0 or 1 items.
Returns `null` if the list is empty. Errors if the list has 2+ items.
Used to safely dereference `count`-based resources.

```hcl
# Instead of: aws_eip.this[0].id  (errors if count = 0)
# Use:
one(aws_eip.this[*].id)   # returns null if not created, ID if created
```

**Practice in console:**
```
> one(["only-value"])
"only-value"

> one([])
null
```

---

## 11b. `for` expression — building a map from a set of objects (ACM pattern)

Used when AWS returns a **set of objects** and you need a map for stable `for_each` iteration.
Real example: ACM returns `domain_validation_options` — one object per domain on the cert.

```hcl
# ACM produces this automatically after certificate creation:
# domain_validation_options = [
#   { domain_name="coolteddy.io",   resource_record_name="_abc.coolteddy.io", ... },
#   { domain_name="*.coolteddy.io", resource_record_name="_abc.coolteddy.io", ... }
# ]

# Convert set of objects → map keyed by domain name:
for_each = {
  for dvo in aws_acm_certificate.regional.domain_validation_options :
  dvo.domain_name => dvo        # key = domain name, value = whole object
}

# for_each now has:
# { "coolteddy.io" = {object}, "*.coolteddy.io" = {object} }
# Creates one Route 53 record per entry — each.value is the whole dvo object

# Conditional version — guard when resource might not exist:
for_each = var.create_cloudfront_cert ? {
  for dvo in aws_acm_certificate.cloudfront[0].domain_validation_options :
  dvo.domain_name => dvo
} : {}    # {} = empty map = zero resources created
```

**Practice in console:**
```
# Simulate domain_validation_options
> {for dvo in [{domain_name="coolteddy.io"}, {domain_name="*.coolteddy.io"}] : dvo.domain_name => dvo}
{
  "*.coolteddy.io" = { "domain_name" = "*.coolteddy.io" }
  "coolteddy.io"   = { "domain_name" = "coolteddy.io" }
}

# Conditional guard — true returns map, false returns empty map
> true  ? {for d in ["a","b"] : d => d} : {}
{ "a" = "a", "b" = "b" }

> false ? {for d in ["a","b"] : d => d} : {}
{}

# Access a field from the object (simulates each.value.resource_record_name)
> [{domain_name="coolteddy.io", record="_abc.coolteddy.io"}][0].record
"_abc.coolteddy.io"
```

---

## 12. `setproduct()` — all combinations of two lists

Generates every combination of elements from two (or more) lists.
Like a multiplication table. Useful for building rules across multiple dimensions.

```hcl
setproduct([443, 80], ["10.0.0.0/8", "192.168.0.0/16"])
# → [[443, "10.0.0.0/8"], [443, "192.168.0.0/16"],
#    [80,  "10.0.0.0/8"], [80,  "192.168.0.0/16"]]
```

**Practice in console:**
```
> setproduct(["a", "b"], ["x", "y"])
[
  ["a", "x"],
  ["a", "y"],
  ["b", "x"],
  ["b", "y"],
]
```

---

# SECTION B — String Functions

## 13. `format()`

Formats a string using printf-style placeholders. Cleaner than string interpolation
for complex strings.

```hcl
format("arn:aws:s3:::%s", "my-bucket")
# → "arn:aws:s3:::my-bucket"

format("%s-%s-%03d", "sandbox", "vpc", 1)
# → "sandbox-vpc-001"
```

**Practice in console:**
```
> format("Hello, %s!", "world")
"Hello, world!"

> format("%s-%s", "eu-west", "1")
"eu-west-1"
```

---

## 14. `join()` and `split()`

`join()` combines a list into a single string with a separator.
`split()` does the opposite — splits a string into a list.

```hcl
join(", ", ["10.0.0.0/24", "10.0.1.0/24"])
# → "10.0.0.0/24, 10.0.1.0/24"

split(",", "eu-west-1a,eu-west-1b,eu-west-1c")
# → ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
```

**Practice in console:**
```
> join(", ", ["a", "b", "c"])
"a, b, c"

> split(",", "eu-west-1a,eu-west-1b")
["eu-west-1a", "eu-west-1b"]
```

---

## 15. `replace()` and `trimspace()`

`replace()` substitutes a substring. `trimspace()` removes leading/trailing whitespace.

```hcl
replace("eu-west-1", "-", "_")   # → "eu_west_1"
trimspace("  hello  ")            # → "hello"
```

**Practice in console:**
```
> replace("eu-west-1", "-", "_")
"eu_west_1"

> trimspace("  hello world  ")
"hello world"
```

---

## 16. `lower()`, `upper()`, `title()`

Change string casing. Useful for normalising tag values or region names.

```hcl
lower("EU-WEST-1")    # → "eu-west-1"
upper("eu-west-1")    # → "EU-WEST-1"
title("hello world")  # → "Hello World"
```

**Practice in console:**
```
> lower("MY-BUCKET")
"my-bucket"

> upper("sandbox")
"SANDBOX"
```

---

## 17. `substr()`

Extracts part of a string by offset and length.
`-1` as length means "to the end of the string".

```hcl
substr("eu-west-1a", 0, 9)    # → "eu-west-1"  (region without AZ letter)
substr("eu-west-1a", -1, 1)   # → "a"           (last character = AZ letter)
```

**Practice in console:**
```
> substr("eu-west-1a", -1, 1)
"a"

> substr("eu-west-1a", 0, 9)
"eu-west-1"
```

---

# SECTION C — Encoding Functions

## 18. `jsonencode()` and `jsondecode()`

`jsonencode()` converts a Terraform value to a JSON string.
Essential for inline IAM policies, ECS task definitions, and Lambda config.

```hcl
jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect   = "Allow"
    Action   = ["s3:GetObject"]
    Resource = "arn:aws:s3:::my-bucket/*"
  }]
})
```

`jsondecode()` parses a JSON string back into a Terraform value.

**Practice in console:**
```
> jsonencode({"key" = "value", "number" = 42})
"{\"key\":\"value\",\"number\":42}"

> jsondecode("{\"a\":\"1\"}")
{
  "a" = "1"
}
```

---

## 19. `base64encode()` and `base64decode()`

`base64encode()` converts a string to base64. Required for EC2 `user_data`.
`base64decode()` reverses it.

```hcl
# EC2 user_data must be base64-encoded
user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
  db_host = aws_db_instance.this.address
}))
```

**Practice in console:**
```
> base64encode("hello world")
"aGVsbG8gd29ybGQ="

> base64decode("aGVsbG8gd29ybGQ=")
"hello world"
```

---

# SECTION D — Error Handling

## 20. `try()` and `can()`

`try()` evaluates an expression and returns the first one that doesn't error.
`can()` returns true if an expression succeeds, false if it errors.
Used to safely access values that might not exist.

```hcl
# Return the value if it exists, or a default if it errors
try(var.optional_config.timeout, 30)

# Check if a key exists in a map before using it
can(var.config["optional_key"])   # true or false
```

**Practice in console:**
```
> try("value", "default")
"value"

> can(tonumber("not-a-number"))
false

> can(tonumber("443"))
true
```

---

# SECTION E — Path References

## 21. `path.module`, `path.root`, `path.cwd`

Built-in values that return filesystem paths. Essential when using `file()` or `templatefile()`.

```hcl
path.module   # path to the current module's directory
path.root     # path to the root module (where you ran terraform)
path.cwd      # current working directory of the terraform process
```

```hcl
# Always use path.module when referencing files inside a module
user_data = file("${path.module}/scripts/bootstrap.sh")
policy    = file("${path.module}/policies/s3-read.json")
```

**Practice in console:**
```
> path.module
"."

> path.cwd
"/Users/you/devops/my-project"
```

---

# SECTION F — Resource & Meta-Arguments

## 22. `for` expression — list transformation

Transforms one list into another. Syntax: `[for item in list : expression]`

```hcl
[for p in [443, 80] : tostring(p)]           # → ["443", "80"]
[for p in [22, 443, 8080] : p if p > 1000]  # → [8080]  (filtered)
[for s in ["hello", "world"] : upper(s)]     # → ["HELLO", "WORLD"]
```

**Practice in console:**
```
> [for p in [443, 80, 22] : tostring(p)]
["443", "80", "22"]

> [for p in [443, 80, 22] : p if p > 80]
[443]
```

---

## 23. `for` expression — map transformation

Produces a map. Syntax: `{for item in list : key => value}`

```hcl
{for az in ["eu-west-1a", "eu-west-1b"] : az => substr(az, -1, 1)}
# → {"eu-west-1a" = "a", "eu-west-1b" = "b"}
```

**Practice in console:**
```
> {for az in ["eu-west-1a", "eu-west-1b"] : az => substr(az, -1, 1)}
{
  "eu-west-1a" = "a"
  "eu-west-1b" = "b"
}
```

---

## 24. `for_each` with `toset()`

Creates one resource per element. Element is both `each.key` and `each.value`.
Stable — removing one element destroys only that resource.

```hcl
resource "aws_vpc_security_group_ingress_rule" "ports" {
  for_each  = toset(["443", "80"])
  from_port = tonumber(each.value)
  to_port   = tonumber(each.value)
}
# State: ports["443"], ports["80"]
```

---

## 25. `for_each` with a `map`

`each.key` and `each.value` carry different information — used in VPC subnets.

```hcl
resource "aws_subnet" "public" {
  for_each          = {"eu-west-1a" = "10.0.0.0/24", "eu-west-1b" = "10.0.1.0/24"}
  availability_zone = each.key     # "eu-west-1a"
  cidr_block        = each.value   # "10.0.0.0/24"
}
```

---

## 26. `count` — conditional or repeated resources

```hcl
resource "aws_eip" "this" {
  count = var.create_elastic_ip ? 1 : 0
}
# Reference: aws_eip.this[0].id
# Safe reference: one(aws_eip.this[*].id)
```

---

## 27. `dynamic` block

Conditionally creates a nested block inside a resource. Only for blocks — not plain attributes.
The trick: `[1]` means "loop once = create the block", `[]` means "loop zero times = skip the block".

```hcl
# Simple on/off — create the block when enabled
dynamic "access_logs" {
  for_each = var.enable_logs ? [1] : []
  content {
    bucket = var.log_bucket
  }
}

# Loop over a list — one block per item
dynamic "ingress" {
  for_each = var.cors_rules
  content {
    allowed_origins = ingress.value.allowed_origins
    allowed_methods = ingress.value.allowed_methods
  }
}

# Nested dynamic — dynamic inside dynamic
# Outer: one lifecycle rule per item in list
# Inner: conditionally include transition block only when days > 0
dynamic "rule" {
  for_each = var.lifecycle_rules
  content {
    id     = rule.value.id
    status = "Enabled"

    dynamic "transition" {
      for_each = rule.value.transition_days > 0 ? [1] : []
      content {
        days          = rule.value.transition_days
        storage_class = "STANDARD_IA"
      }
    }
  }
}
```

**Why nested dynamic?**
The outer `dynamic "rule"` creates one lifecycle rule per item in the list.
Inside each rule, some sub-blocks are optional (transition, expiration).
You can't use `if` inside a `content {}` block — the only way to conditionally
include a nested block is another `dynamic`. That's why dynamic blocks nest.

**Practice in console:**
The Terraform console cannot render resource blocks directly, but you can
practice the expressions that CONTROL dynamic blocks:

```
# Simulating the on/off condition
> true ? [1] : []
[1]

> false ? [1] : []
[]

# Simulating a days condition (would create the transition block)
> 30 > 0 ? [1] : []
[1]

# Simulating a days condition (would SKIP the transition block)
> 0 > 0 ? [1] : []
[]

# Simulating the outer loop — what each rule.value looks like
> [for r in [{id="rule1", transition_days=30}, {id="rule2", transition_days=0}] : r.id]
["rule1", "rule2"]

# Simulating which rules would get a transition block
> [for r in [{id="rule1", transition_days=30}, {id="rule2", transition_days=0}] : r.id if r.transition_days > 0]
["rule1"]

# Full simulation — what for_each produces per rule
> {for r in [{id="rule1", transition_days=30}, {id="rule2", transition_days=0}] : r.id => (r.transition_days > 0 ? "transition CREATED" : "transition SKIPPED")}
{
  "rule1" = "transition CREATED"
  "rule2" = "transition SKIPPED"
}
```

---

## 28. `contains()`, `merge()`, `validation`

```hcl
contains(["gp2", "gp3"], "gp3")   # true

merge({"Env" = "prod"}, {"Name" = "vpc"})   # {"Env" = "prod", "Name" = "vpc"}

variable "type" {
  validation {
    condition     = contains(["gp2", "gp3"], var.type)
    error_message = "Must be gp2 or gp3."
  }
}
```

---

## 29. `locals` and `sensitive`

```hcl
locals {
  prefix = "${var.project}-${var.env}"
}

variable "db_password" {
  type      = string
  sensitive = true   # hidden from terminal output
}
```

---

## 30. `lifecycle` blocks

```hcl
lifecycle {
  create_before_destroy = true    # zero downtime updates
  prevent_destroy       = true    # block accidental destroy (RDS)
  ignore_changes        = [ami]   # don't react to out-of-band changes
}
```

---

# SECTION G — State & Workspaces

## 31. Backend configuration — remote state with S3 + DynamoDB

Terraform stores state locally by default (`terraform.tfstate`).
In production, use an S3 backend with DynamoDB for locking — prevents two engineers
from running `terraform apply` at the same time and corrupting state.

```hcl
# In terraform {} block (usually backend.tf)
terraform {
  backend "s3" {
    bucket         = "my-company-terraform-state"
    key            = "sandbox/vpc/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

DynamoDB table needs a `LockID` primary key (String). One table can serve all environments.

```bash
terraform init   # initialises the backend and downloads state from S3
```

---

## 32. `terraform_remote_state` — read another module's outputs

Lets one Terraform config read the outputs of another without them being in the same state.
Used when the VPC is managed separately from the app layer.

```hcl
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "my-company-terraform-state"
    key    = "sandbox/vpc/terraform.tfstate"
    region = "eu-west-1"
  }
}

# Use its outputs directly
resource "aws_instance" "app" {
  subnet_id = data.terraform_remote_state.vpc.outputs.private_subnet_ids[0]
}
```

---

## 33. `moved` block — refactor without destroying resources

When you rename a resource or move it into a module, Terraform would normally destroy
the old one and create a new one. The `moved` block tells Terraform they are the same thing.

```hcl
# You renamed aws_instance.server to aws_instance.this
moved {
  from = aws_instance.server
  to   = aws_instance.this
}

# You moved a resource into a module
moved {
  from = aws_security_group.alb
  to   = module.alb.aws_security_group.alb
}
```

After the next `terraform apply`, remove the `moved` block. It's only needed once.

---

## 34. `terraform.workspace` — workspaces for environment separation

Workspaces let you use the same Terraform code for multiple environments
(dev, staging, prod) with separate state files.

```bash
terraform workspace new staging     # create a new workspace
terraform workspace select prod     # switch to prod
terraform workspace list            # show all workspaces
terraform workspace show            # show current workspace
```

```hcl
# Use workspace name in resource naming
locals {
  env = terraform.workspace   # "default", "staging", "prod"
}

resource "aws_s3_bucket" "app" {
  bucket = "my-company-app-${local.env}"
}
```

**Caution:** For large orgs, separate state files per environment (different S3 keys) are safer than workspaces. Workspaces are good for short-lived environments.

---

## 35. `data` sources — read existing AWS resources

```hcl
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

data "aws_caller_identity" "current" {}   # get current AWS account ID
data "aws_region" "current" {}            # get current region

# Use them
resource "aws_instance" "this" {
  ami = data.aws_ami.al2023.id
}

output "account_id" {
  value = data.aws_caller_identity.current.account_id
}
```

---

## 36. `templatefile()` and `file()`

```hcl
user_data = file("${path.module}/user_data.sh")

user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
  db_host = aws_db_instance.this.address
  region  = var.region
}))
```

---

## 37. `terraform apply -replace` — force resource recreation

```bash
terraform apply -replace="aws_instance.this"
terraform apply -replace='aws_vpc_security_group_ingress_rule.ports["443"]'
terraform plan  -replace="aws_instance.this"   # preview first
```

`terraform taint` was deprecated in Terraform 0.15.2 — do not use it.

---

# SECTION H — Useful CLI Commands

## 38. Essential Terraform CLI

```bash
terraform init              # download providers, initialise backend
terraform init -upgrade     # upgrade providers to latest allowed version
terraform fmt               # auto-format all .tf files
terraform validate          # check syntax without hitting AWS
terraform plan              # preview changes
terraform apply             # apply changes (prompts for confirmation)
terraform apply -auto-approve  # apply without prompt (use in CI only)
terraform destroy           # destroy all resources
terraform output            # show all outputs
terraform output vpc_id     # show specific output
terraform state list        # list all resources in state
terraform state show 'aws_instance.this'   # inspect one resource
terraform console           # interactive expression evaluator
```

---

# Quick Reference — when to use what

| Need | Use |
|---|---|
| Create N resources from a list | `for_each = toset(list)` |
| Create N resources from key-value pairs | `for_each = map` |
| Create 0 or 1 resource conditionally | `count = condition ? 1 : 0` |
| Transform a list into another list | `[for x in list : expression]` |
| Transform a list into a map | `{for x in list : key => value}` |
| All combinations of two lists | `setproduct(list1, list2)` |
| Merge maps (tags) | `merge(map1, map2)` |
| Join two lists | `concat(list1, list2)` |
| Flatten nested lists | `flatten([[a,b],[c,d]])` |
| Remove nulls/empties from list | `compact(list)` |
| Remove duplicates | `distinct(list)` |
| Two lists → one map | `zipmap(keys_list, values_list)` |
| Safe map key read | `lookup(map, key, default)` |
| All map keys | `keys(map)` |
| All map values | `values(map)` |
| Count items | `length(list_or_map)` |
| Safe single item from count resource | `one(resource[*].attr)` |
| Check if value is in list | `contains(list, value)` |
| Convert number to string | `tostring(number)` |
| Convert string to number | `tonumber(string)` |
| Convert list to set | `toset(list)` |
| Join list to string | `join(separator, list)` |
| Split string to list | `split(separator, string)` |
| IAM policy as string | `jsonencode({...})` |
| EC2 user_data encoding | `base64encode(string)` |
| Safe expression (no error) | `try(expr, default)` |
| Check expression succeeds | `can(expression)` |
| File path in module | `path.module` |
| Force resource recreation | `terraform apply -replace="resource.name"` |
| Refactor without destroying | `moved {}` block |
| Read another state's outputs | `data.terraform_remote_state` |
| Current environment name | `terraform.workspace` |
