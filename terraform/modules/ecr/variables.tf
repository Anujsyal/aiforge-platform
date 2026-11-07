variable "prefix" {
  type    = string
  default = "aiforge"
}

variable "repositories" {
  type    = list(string)
  default = ["rag-app", "backstage"]
}

variable "keep_images" {
  type    = number
  default = 30
}

variable "force_delete" {
  description = "true = destroy pe images ke saath repo delete (lab ke liye theek)"
  type        = bool
  default     = true
}
