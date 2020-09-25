# completion-tags
Tags autocompletion source for [completion-nvim](https://github.com/nvim-lua/completion-nvim)

It works almost the same as built-in `tags` completion, with additional floating window that contains paths where tag is pulled from.

![screenshot](https://i.imgur.com/cDMdWhq.png)

## Installation

Use your favorite plugin manager to install it, and add `tags` to the chain completion list:

```vimL
function! PackagerInit()
  call packager#add('kristijanhusak/vim-packager')
  call packager#add('nvim-lua/completion-nvim')
  call packager#add('kristijanhusak/completion-tags')
endfunction

let g:completion_chain_complete_list = {
      \ 'default': [
      \    {'complete_items': ['lsp']},
      \    {'complete_items': ['tags']},
      \  ]}

" Or combine with lsp
let g:completion_chain_complete_list = {
      \ 'default': [
      \    {'complete_items': ['lsp', 'tags']},
      \  ]}
```
