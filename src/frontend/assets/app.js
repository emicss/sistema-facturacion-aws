import {request,session,signIn,signOut} from './api.js';
import {esc,button,field,form,dialog,notice} from './ui.js';
import {services} from './catalog.js';
import {cart,invoices,recover} from './billing.js';
import {reports,audit,users} from './reports.js';

const root=document.querySelector('#app');
const brand='<div class="brand"><i aria-hidden="true">C</i> CloudTech</div>';
const pages={
  catalogo:['Catálogo','Catálogo de servicios','Consulta las especificaciones y tarifas de los servicios cloud.',services,'▦'],
  carrito:['Carrito','Carrito de servicios','Revisa las cantidades y los importes antes de emitir.',cart,'▤'],
  facturas:['Facturas','Facturas','Consulta comprobantes, movimientos de cobranza y saldos.',invoices,'▧'],
  reportes:['Reportes','Reportes fiscales','Consulta el cierre por periodo y la antigüedad de la cartera.',reports,'▥'],
  auditoria:['Auditoría','Auditoría de eventos','Consulta el historial de operaciones registrado en DynamoDB.',audit,'◷'],
  usuarios:['Usuarios','Control de acceso','Registra una cuenta y asigna sus permisos de operación.',users,'⊙']
};
let version=0;
function login() {
  root.innerHTML='<main class="login"><section class="cover">'+brand+
    '<div class="cover-content"><div class="eyebrow"><b></b> Consola fiscal</div><h1>Facturación<br><em>cloud.</em></h1>'+
    '<div class="receipt-art" aria-hidden="true"><div class="orbit"></div><div class="paper back"></div><div class="paper front"><div class="paper-top"><b>CFDI</b><span>4.0</span></div><div class="rule"></div><div class="bars"></div><div class="paper-bottom"><i></i><b>MXN</b></div></div></div></div>'+
    '<div class="cover-foot">CloudTech Systems <span>Servicios en la nube</span></div></section>'+
    '<section class="login-side"><div class="login-box"><div class="eyebrow"><b></b> Acceso al sistema</div><h2>Iniciar sesión</h2><p>Ingresa con tu cuenta de CloudTech.</p><div id="login-form"></div></div></section></main>';
  form(root.querySelector('#login-form'),field('email','Correo electrónico','email','autocomplete="username" placeholder="nombre@empresa.mx"')+
    field('password','Contraseña','password','autocomplete="current-password" placeholder="Ingresa tu contraseña"'),'Entrar a la consola  →',async data=>{
    signIn(await request('/auth/login','POST',data));await render();
  });
}
async function render() {
  const current=++version;
  if (dialog.open) dialog.close();
  const auth=session();
  if (!auth) {login();return;}
  const user=auth.usuario;
  const admin=user.rol==='ADMIN',finance=admin || user.rol==='CONTADOR',issue=admin || user.rol==='OPERADOR';
  const allowed=['catalogo','carrito','facturas',...(finance?['reportes','auditoria']:[]),...(admin?['usuarios']:[])];
  const requested=location.hash.slice(1);
  const page=allowed.includes(requested)?requested:'catalogo';
  if (requested!==page) history.replaceState(null,'','#'+page);
  const [name,title,subtitle,view]=pages[page];
  root.innerHTML='<div class="workspace"><aside class="rail">'+brand+'<nav aria-label="Navegación principal">'+allowed.map(id=>
    '<a href="#'+id+'" '+(page===id?'aria-current="page"':'')+'><i aria-hidden="true">'+pages[id][4]+'</i>'+pages[id][0]+(id==='carrito'?'<small class="count"></small>':'')+'</a>').join('')+'</nav><div class="account"><b>'+esc(user.nombre_completo)+'</b><small>'+esc(user.rol)+'</small>'+button('exit','Cerrar sesión')+'</div></aside><main class="desk"><header class="crumb">Consola fiscal <span>/</span> '+name+'</header><div class="content"><div class="eyebrow"><b></b> CloudTech Systems</div><h1>'+title+'</h1><p class="subtitle">'+subtitle+'</p><div id="pending"></div><section class="panel" aria-label="'+title+'"><p role="status">Cargando…</p></section></div></main></div>';
  const el=root.querySelector('.panel');
  const ctx={admin,finance,issue,userId:user.id_usuario,active:()=>version===current,refresh:render,
    pending:()=>recover(root.querySelector('#pending'),ctx),
    setCount:items=>{if (current===version) root.querySelector('.count').textContent=items.length;},
    count:async()=>{
      try {
        const {items}=await request('/carrito');
        ctx.setCount(items);
      } catch(error) {if (ctx.active()) notice(error.message);}
    },
    actions:(container,handler)=>{
      container.onclick=async event=>{
        const btn=event.target.closest('button[data-action]');
        if (!btn || container.inert) return;
        container.inert=true;
        try {await handler(btn.dataset.action,btn.dataset.id);}
        catch(error) {notice(error.message);}
        finally {container.inert=false;}
      };
    }
  };
  root.querySelector('[data-action="exit"]').onclick=signOut;
  ctx.pending();
  if (page!=='carrito') void ctx.count();
  try {
    await view(el,ctx);

  } catch(error) {
    el.innerHTML='<p class="error" role="alert">'+esc(error.message)+'</p>'+button('reload','Volver a cargar');
    ctx.actions(el,render);
  }
}
window.addEventListener('hashchange',render);
window.addEventListener('session-ended',()=>{history.replaceState(null,'',location.pathname+location.search);render();});
render();
