"use strict";var c=Object.defineProperty;var P=Object.getOwnPropertyDescriptor;var y=Object.getOwnPropertyNames;var F=Object.prototype.hasOwnProperty;var D=(e,t)=>{for(var n in t)c(e,n,{get:t[n],enumerable:!0})},S=(e,t,n,r)=>{if(t&&typeof t=="object"||typeof t=="function")for(let o of y(t))!F.call(e,o)&&o!==n&&c(e,o,{get:()=>t[o],enumerable:!(r=P(t,o))||r.enumerable});return e};var v=e=>S(c({},"__esModule",{value:!0}),e);var I={};D(I,{default:()=>d});module.exports=v(I);var h=require("@raycast/api");var a=require("@raycast/api"),m=require("os"),f=require("path"),O=(0,a.getPreferenceValues)(),b=(0,m.homedir)(),g=O.repoPath,z=g?(0,f.join)(g,"config"):"";function i(e,t){return{homeRelative:e,repoRelative:t,homePath:(0,f.join)(b,e),repoPath:(0,f.join)(z,t),name:t.split("/").pop()||t}}var l=[i(".zshrc","zsh/zshrc"),i(".zprofile","zsh/zprofile"),i(".config/git/config","git/config"),i(".config/git/ignore","git/ignore"),i(".config/git/gh-config","git/gh-config"),i(".config/git/gl-config","git/gl-config"),i(".editorconfig","editorconfig"),i(".config/tmux/tmux.conf","tmux/tmux.conf"),i(".config/nvim/init.lua","nvim/init.lua"),i(".config/vim/vimrc","vim/vimrc"),i(".config/gdb/gdbinit","gdb/gdbinit"),i(".config/ghostty/config","ghostty/config"),i("Library/Application Support/Code/User/settings.json","vscode/settings.json"),i(".config/zed/settings.json","zed/settings.json"),i(".config/ruff/ruff.toml","ruff/ruff.toml")];var s=require("fs");var u=require("@raycast/api");function E(e,t){try{if(!(0,s.existsSync)(e)||!(0,s.existsSync)(t))return!1;let n=(0,s.readFileSync)(e,"utf8"),r=(0,s.readFileSync)(t,"utf8");return n===r}catch{return!1}}function p(e){let t=(0,s.existsSync)(e.repoPath),n=(0,s.existsSync)(e.homePath);return t&&n?E(e.repoPath,e.homePath)?"\u2705":"\u{1F504}":t&&!n?"\u{1F4E5}":!t&&n?"\u{1F4E4}":"\u274C"}var x=require("react/jsx-runtime");function d(){return(0,x.jsx)(h.Detail,{markdown:(()=>{let t=`# \u{1F4CB} Dotfiles Status

`;for(let n of l){let r=p(n);t+=`## ${r} ${n.name}

`,t+=`**Repo Path:** \`${n.repoPath}\`  
`,t+=`**Home Path:** \`${n.homePath}\`  
`;let o="";r==="\u2705"?o="Files are identical":r==="\u{1F504}"?o="Files differ":r==="\u{1F4E5}"?o="Only exists in repo":r==="\u{1F4E4}"?o="Only exists in home":r==="\u274C"&&(o="Missing from both locations"),t+=`**Status:** ${o}

`,t+=`---

`}return t+=`## Legend

`,t+=`- \u2705 Files are identical
`,t+=`- \u{1F504} Files differ
`,t+=`- \u{1F4E5} Only exists in repo
`,t+=`- \u{1F4E4} Only exists in home
`,t+=`- \u274C Missing from both locations
`,t})()})}
