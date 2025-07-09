"use strict";var E=Object.defineProperty;var O=Object.getOwnPropertyDescriptor;var k=Object.getOwnPropertyNames;var C=Object.prototype.hasOwnProperty;var _=(o,n)=>{for(var g in n)E(o,g,{get:n[g],enumerable:!0})},j=(o,n,g,a)=>{if(n&&typeof n=="object"||typeof n=="function")for(let f of k(n))!C.call(o,f)&&f!==g&&E(o,f,{get:()=>n[f],enumerable:!(a=O(n,f))||a.enumerable});return o};var R=o=>j(E({},"__esModule",{value:!0}),o);var T={};_(T,{default:()=>v});module.exports=R(T);var M=require("@raycast/api"),u=require("fs"),y=require("react");var b=require("@raycast/api"),F=require("os"),L=require("path"),A=(0,b.getPreferenceValues)(),H=(0,F.homedir)(),S=A.repoPath,N=S?(0,L.join)(S,"config"):"";function r(o,n){return{homeRelative:o,repoRelative:n,homePath:(0,L.join)(H,o),repoPath:(0,L.join)(N,n),name:n.split("/").pop()||n}}var w=[r(".zshrc","zsh/zshrc"),r(".zprofile","zsh/zprofile"),r(".config/git/config","git/config"),r(".config/git/ignore","git/ignore"),r(".config/git/gh-config","git/gh-config"),r(".config/git/gl-config","git/gl-config"),r(".editorconfig","editorconfig"),r(".config/tmux/tmux.conf","tmux/tmux.conf"),r(".config/nvim/init.lua","nvim/init.lua"),r(".config/vim/vimrc","vim/vimrc"),r(".config/gdb/gdbinit","gdb/gdbinit"),r(".config/ghostty/config","ghostty/config"),r("Library/Application Support/Code/User/settings.json","vscode/settings.json"),r(".config/zed/settings.json","zed/settings.json"),r(".config/ruff/ruff.toml","ruff/ruff.toml")];var I=require("react/jsx-runtime");function V(o,n,g){let a=o.split(`
`),f=n.split(`
`),t=Math.max(a.length,f.length),p=!1,e="",s=null,h=3,c=[];for(let i=0;i<t;i++){let m=a[i]||"",l=f[i]||"";m!==l?(p=!0,s||(s={start:Math.max(0,i-h),end:i}),s.end=Math.min(t-1,i+h)):s&&i>s.end&&(c.push(s),s=null)}return s&&c.push(s),p?(e+=`## \u{1F4C4} ${g}

`,c.forEach((i,m)=>{m>0&&(e+=`
---

`),e+=`**Lines ${i.start+1}-${i.end+1}:**

`,e+=`| \u{1F3E0} Home Version | \u{1F4E6} Repo Version |
`,e+=`|-----------------|------------------|
`;for(let l=i.start;l<=i.end;l++){let P=a[l]||"",$=f[l]||"",d=l+1,x=z($),D=z(P);P===$?e+=`| \`${d}: ${x}\` | \`${d}: ${D}\` |
`:$&&P?e+=`| \`- ${d}: ${x}\` | \`+ ${d}: ${D}\` |
`:$&&!P?e+=`| \`- ${d}: ${x}\` |  |
`:!$&&P&&(e+=`|  | \`+ ${d}: ${D}\` |
`)}e+=`
`}),e+=`---

`,e):""}function z(o){return o.replace(/\\/g,"\\\\").replace(/\|/g,"\\|").replace(/`/g,"\\`").replace(/\*/g,"\\*").replace(/_/g,"\\_").replace(/~/g,"\\~").replace(/\[/g,"\\[").replace(/\]/g,"\\]").replace(/\(/g,"\\(").replace(/\)/g,"\\)").replace(/#/g,"\\#").replace(/\+/g,"\\+").replace(/-/g,"\\-").replace(/!/g,"\\!").replace(/</g,"&lt;").replace(/>/g,"&gt;")}function v(){let[o,n]=(0,y.useState)(!0),[g,a]=(0,y.useState)("");(0,y.useEffect)(()=>{f()},[]);let f=()=>{n(!0);let t=`# \u{1F50D} Dotfiles Differences

`,p=!1;for(let e of w){let s=(0,u.existsSync)(e.repoPath),h=(0,u.existsSync)(e.homePath);if(!s||!h){p=!0,t+=`## \u26A0\uFE0F File Missing: ${e.name}

`,s||(t+=`> \u{1F4E6} \`${e.repoPath}\` does not exist in the repository.
`),h||(t+=`> \u{1F3E0} \`${e.homePath}\` does not exist in the home directory.
`),t+=`---

`;continue}try{let c=(0,u.readFileSync)(e.repoPath,"utf8"),i=(0,u.readFileSync)(e.homePath,"utf8");if(c!==i){p=!0,t+=`*Side-by-side comparison of your dotfiles*

`;let m=V(c,i,e.name);m&&(t+=`> **\u{1F4CD} File paths:**
`,t+=`> \u{1F3E0} \`${e.homePath}\`
`,t+=`> \u{1F4E6} \`${e.repoPath}\`

`,t+=m)}}catch(c){t+=`## \u274C Error comparing ${e.name}

`,t+=`Error: ${c instanceof Error?c.message:String(c)}

`,t+=`---

`}}p||(t+=`## **\u2705 No differences found!**
>
`,t+=`> All your dotfiles are perfectly in sync between your repo and home directory. \u{1F389}
`),a(t),n(!1)};return(0,I.jsx)(M.Detail,{markdown:g,isLoading:o})}
