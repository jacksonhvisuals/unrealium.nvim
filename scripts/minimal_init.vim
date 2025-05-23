set rtp+=.
set rtp+=../plenary.nvim/
set rtp+=../vim-dispatch/
set rtp+=../vim-dispatch-neovim/
set rtp+=../telescope.nvim/
set rtp+=../tree-sitter-lua/

runtime! plugin/plenary.vim
runtime! plugin/dispatch.vim
runtime! plugin/unrealium.lua

let g:telescope_test_delay = 100
