(()=>{let x=window;if(x.__uidotshPickerLoaded)return;x.__uidotshPickerLoaded=!0;const p="[data-uidotsh-pick]",h="[data-uidotsh-option]",m="uidotsh-picker";function w(o,e){let n=o?.trim()??"";return n.length>0?n:e}function P(){let o=document.querySelector(p);if(!o)return null;let e=[],n=0;for(let i of o.querySelectorAll(h))i.closest(p)===o&&(n+=1,e.push({label:w(i.getAttribute("data-uidotsh-option"),`Option ${n}`),element:i}));return{label:w(o.getAttribute("data-uidotsh-pick"),"Decision 1"),options:e}}function E(o){return Math.max(0,o.options.findIndex(e=>!e.element.hidden))}function y(o,e){let n=e??o.options.find(r=>!r.element.hidden)??o.options[0];if(!n)return!1;let i=!1;for(let r of o.options){let a=r.element,d=r!==n;a.hidden!==d&&(a.hidden=d,i=!0),d?a.style.display="none":a.style.removeProperty("display")}return i}function v(o){return o instanceof Element?o.matches(p)||o.matches(h)?!0:o.querySelector(p)!==null||o.querySelector(h)!==null:!1}class T extends HTMLElement{root;popoverElement;previousButton;nextButton;positionText;select;group=null;onSelect=null;constructor(){super(),this.root=this.attachShadow({mode:"open"}),this.root.innerHTML=`
        <style>
          :host {
            display: block;
            position: fixed;
            width: 0;
            height: 0;
            overflow: visible;
            color: #ffffff;
            font-family: ui-sans-serif, system-ui, sans-serif;
            line-height: 1;
          }

          *, *::before, *::after {
            box-sizing: border-box;
          }

          [data-popover] {
            display: block;
            position: fixed;
            left: 50%;
            right: auto;
            top: auto;
            bottom: 16px;
            transform: translateX(-50%);
            margin: 0;
            padding: 0;
            border: 0;
            width: auto;
            max-width: calc(100vw - 16px);
            background: transparent;
            color: inherit;
            overflow: visible;
            outline: none;
          }

          [data-panel] {
            display: grid;
            grid-template-columns: auto auto 1fr auto auto;
            align-items: stretch;
            min-width: 16rem;
            height: 40px;
            border-radius: 12px;
            padding: 4px;
            background: rgba(10, 10, 10, 0.8);
            box-shadow:
              0 0 0 1px rgba(0, 0, 0, 0.9),
              inset 0 0 0 1px rgba(255, 255, 255, 0.1),
              0 25px 50px -12px rgba(0, 0, 0, 0.5);
            backdrop-filter: blur(24px);
            -webkit-backdrop-filter: blur(24px);
          }

          [data-nav] {
            width: 32px;
            height: 32px;
            border: 0;
            border-radius: 8px;
            display: inline-flex;
            align-items: center;
            justify-content: center;
            color: #a3a3a3;
            background: transparent;
            cursor: pointer;
            transition: color 120ms ease, background-color 120ms ease, opacity 120ms ease;
          }

          [data-nav]:hover {
            color: #ffffff;
            background: rgba(255, 255, 255, 0.1);
          }

          [data-nav]:focus-visible {
            color: #ffffff;
            background: rgba(255, 255, 255, 0.1);
            outline: none;
          }

          [data-nav]:disabled {
            opacity: 0.45;
            cursor: default;
          }

          [data-divider-wrap] {
            display: flex;
            align-items: center;
            padding: 0 4px;
          }

          [data-divider] {
            width: 1px;
            height: 16px;
            background: rgba(255, 255, 255, 0.12);
          }

          [data-center] {
            position: relative;
            min-width: 0;
            border-radius: 8px;
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 0 8px;
            color: #ffffff;
            cursor: pointer;
            transition: background-color 120ms ease;
          }

          [data-center]:hover {
            background: rgba(255, 255, 255, 0.1);
          }

          [data-center]:focus-within {
            background: rgba(255, 255, 255, 0.1);
          }

          [data-meta] {
            min-width: 0;
            flex: 1;
            display: flex;
            align-items: baseline;
            gap: 8px;
          }

          [data-position] {
            flex-shrink: 0;
            font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
            font-size: 12px;
            color: rgba(255, 255, 255, 0.5);
          }

          [data-select] {
            min-width: 0;
            flex: 1;
            border: 0;
            outline: none;
            color: #ffffff;
            background: transparent;
            appearance: none;
            font-size: 13px;
            font-weight: 500;
            text-align: center;
            white-space: nowrap;
            text-overflow: ellipsis;
            overflow: hidden;
            padding-right: 18px;
            cursor: pointer;
          }

          [data-select]:disabled {
            cursor: default;
            color: rgba(255, 255, 255, 0.6);
          }

          [data-select]:focus-visible {
            outline: none;
          }

          [data-chevron] {
            position: absolute;
            right: 8px;
            width: 14px;
            height: 14px;
            color: #737373;
            pointer-events: none;
            transform: rotate(180deg);
          }

          @media (max-width: 640px) {
            [data-popover] {
              left: 8px;
              bottom: 8px;
              transform: none;
              max-width: calc(100vw - 16px);
            }

            [data-panel] {
              min-width: calc(100vw - 16px);
            }
          }
        </style>

        <div popover="manual" data-popover aria-label="UI picker" tabindex="-1">
          <section data-panel>
            <button type="button" data-nav data-previous aria-label="Previous section">
              <svg viewBox="0 0 5 6" fill="currentColor" width="5" height="6" aria-hidden="true">
                <path d="M0.75 3L4.25 5.25L4.25 0.75L0.75 3Z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" />
              </svg>
            </button>
            <div data-divider-wrap><div data-divider></div></div>
            <div data-center>
              <span data-meta>
                <span data-position>0/0</span>
                <select data-select aria-label="Select option"></select>
              </span>
              <svg viewBox="0 0 16 16" fill="currentColor" data-chevron aria-hidden="true">
                <path fill-rule="evenodd" d="M4.22 6.22a.75.75 0 0 1 1.06 0L8 8.94l2.72-2.72a.75.75 0 1 1 1.06 1.06l-3.25 3.25a.75.75 0 0 1-1.06 0L4.22 7.28a.75.75 0 0 1 0-1.06Z" clip-rule="evenodd" />
              </svg>
            </div>
            <div data-divider-wrap><div data-divider></div></div>
            <button type="button" data-nav data-next aria-label="Next section">
              <svg viewBox="0 0 5 6" fill="currentColor" width="5" height="6" aria-hidden="true">
                <path d="M4.25 3L0.75 5.25L0.75 0.75L4.25 3Z" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" />
              </svg>
            </button>
          </section>
        </div>
      `;let e=this.root.querySelector("[data-popover]"),n=this.root.querySelector("[data-previous]"),i=this.root.querySelector("[data-next]"),r=this.root.querySelector("[data-center]"),a=this.root.querySelector("[data-position]"),d=this.root.querySelector("[data-select]");if(!(e instanceof HTMLElement)||!(n instanceof HTMLButtonElement)||!(i instanceof HTMLButtonElement)||!(r instanceof HTMLElement)||!(a instanceof HTMLElement)||!(d instanceof HTMLSelectElement))throw new Error("Unable to initialize picker");this.popoverElement=e,this.previousButton=n,this.nextButton=i,this.positionText=a,this.select=d,this.popoverElement.addEventListener("keydown",this.onKeyDown),this.popoverElement.addEventListener("pointerdown",this.onPopoverPointerDown),this.previousButton.addEventListener("click",()=>{this.moveOption(-1)}),this.nextButton.addEventListener("click",()=>{this.moveOption(1)}),this.select.addEventListener("change",()=>{let s=this.group;if(!s)return;let f=s.options[this.select.selectedIndex];f&&this.onSelect?.(f)}),r.addEventListener("pointerdown",s=>{s.button!==0||this.select.disabled||s.target instanceof Element&&s.target.closest("select")||(s.preventDefault(),s.stopPropagation(),this.openSelectMenu())})}connectedCallback(){this.ensurePopoverVisible()}update(e,n){this.group=e,this.onSelect=n,this.render(e),this.ensurePopoverVisible()}raiseToTop(){if(!this.isPopoverOpen()){this.ensurePopoverVisible();return}this.root.activeElement instanceof HTMLSelectElement||(this.popoverElement.hidePopover(),this.popoverElement.showPopover())}isPopoverOpen(){return this.popoverElement.matches(":popover-open")}ensurePopoverVisible(){this.isPopoverOpen()||this.popoverElement.showPopover()}render(e){this.positionText.title=e.label;let n=e.options.length>1;if(this.previousButton.disabled=!n,this.nextButton.disabled=!n,this.select.replaceChildren(),e.options.length===0){let r=document.createElement("option");r.textContent="No variations found",this.select.append(r),this.select.disabled=!0,this.positionText.textContent="0/0";return}let i=E(e);this.positionText.textContent=`${i+1}/${e.options.length}`;for(let r of e.options){let a=document.createElement("option");a.textContent=r.label,this.select.append(a)}this.select.disabled=!1,this.select.selectedIndex=i}moveOption(e){let n=this.group;if(!n||n.options.length<=1)return;let r=(E(n)+e+n.options.length)%n.options.length,a=n.options[r];a&&(this.onSelect?.(a),this.popoverElement.focus({preventScroll:!0}))}openSelectMenu(){if(this.select.disabled)return;this.select.focus({preventScroll:!0});let e=this.select;if(e.showPicker)try{e.showPicker();return}catch{}this.select.click()}onPopoverPointerDown=e=>{e.button===0&&e.target instanceof Element&&(e.target.closest("[data-center]")||e.target.closest("button, select")||this.popoverElement.focus({preventScroll:!0}))};onKeyDown=e=>{if(!(!this.group||e.metaKey||e.ctrlKey||e.altKey)){if((e.key==="ArrowDown"||e.key==="ArrowUp")&&!(this.root.activeElement instanceof HTMLSelectElement)){e.preventDefault(),this.openSelectMenu();return}(e.key==="ArrowLeft"||e.key==="ArrowRight")&&(e.preventDefault(),this.moveOption(e.key==="ArrowRight"?1:-1))}}}customElements.get(m)||customElements.define(m,T);function k(){let o=null,e=!1,n=!1,i=[];function r(){return document.activeElement instanceof Element?document.activeElement.closest("dialog:modal"):null}function a(){i=i.filter(t=>t.isConnected&&t.matches(":modal"))}function d(t){a(),!(!t.isConnected||!t.matches(":modal"))&&(i=i.filter(l=>l!==t),i.push(t))}function s(){a();for(let t of document.querySelectorAll("dialog:modal"))i.includes(t)||i.push(t)}function f(){return s(),r()??i[i.length-1]??null}function C(){return f()??document.body??document.documentElement}function L(){if(!o)return;let t=C();(!o.isConnected||o.parentElement!==t)&&t.append(o)}function S(t){return t instanceof Element?t.matches("dialog, [popover]")||t.querySelector("dialog, [popover]")!==null:!1}function M(t){return t instanceof Element?t.closest('input, textarea, select, [contenteditable=""], [contenteditable="true"]')!==null:!1}function b(){e||(e=!0,requestAnimationFrame(()=>{e=!1,g()}))}function c(){n||(n=!0,requestAnimationFrame(()=>{n=!1,L(),o?.raiseToTop()}))}function g(){let t=P();if(!t){o?.remove(),o=null;return}y(t),o||(o=document.createElement(m)),L(),o.update(t,l=>{y(t,l)&&g()})}new MutationObserver(t=>{for(let l of t){if(l.type==="attributes"){if(l.attributeName==="open"){l.target instanceof HTMLDialogElement&&(d(l.target),c());continue}if(l.attributeName==="popover"){c();continue}if(v(l.target)){b();return}continue}for(let u of l.addedNodes)if(S(u)&&c(),v(u)){b();return}for(let u of l.removedNodes)if(S(u)&&c(),v(u)){b();return}}}).observe(document.documentElement,{subtree:!0,childList:!0,attributes:!0,attributeFilter:["data-uidotsh-pick","data-uidotsh-option","hidden","open","popover"]}),document.addEventListener("click",t=>{t.target instanceof Node&&o?.contains(t.target)||c()},!0),document.addEventListener("keydown",t=>{!o||t.target instanceof Node&&o.contains(t.target)||M(t.target)||M(document.activeElement)||o.onKeyDown(t)},!0),g()}document.readyState==="loading"?document.addEventListener("DOMContentLoaded",k,{once:!0}):k()})();
