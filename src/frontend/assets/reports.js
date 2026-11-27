import {request} from './api.js';
import {esc,label,money,button,badge,table,field,form,select,choices,json,modal,notice} from './ui.js';

function reportTable(rows,amountKeys) {
  const keys=Object.keys(rows[0] || {});
  return table(keys.map(label),rows.map(row=>keys.map(k=>amountKeys.includes(k)?money(row[k]):esc(row[k]))),'Sin resultados en la consulta.');
}
export function reports(el,ctx) {
  el.innerHTML='<h2>Cierre fiscal</h2><div class="report-form"></div><div class="closing"></div><hr><div class="section-head"><h2>Antigüedad de saldos</h2>'+button('aging','Consultar cartera')+'</div><div class="aging"></div>';
  const now=new Date();
  const today=[now.getFullYear(),String(now.getMonth()+1).padStart(2,'0'),String(now.getDate()).padStart(2,'0')].join('-');
  form(el.querySelector('.report-form'),field('fecha_inicio','Desde','date','value="'+today.slice(0,8)+'01"')+field('fecha_fin','Hasta','date','value="'+today+'"'),'Consultar cierre',async data=>{
    if (data.fecha_inicio>data.fecha_fin) throw new Error('La fecha final debe ser igual o posterior a la inicial.');
    const {cierre_fiscal}=await request('/reportes/cierre-fiscal?'+new URLSearchParams(data));
    el.querySelector('.closing').innerHTML=reportTable(cierre_fiscal,['suma_subtotal','suma_descuentos','iva_trasladado','isr_retenido','iva_retenido','total_facturado','total_cobrado']);
  });
  ctx.actions(el,async()=>{
    const {antiguedad_saldos}=await request('/reportes/antiguedad-saldos');
    el.querySelector('.aging').innerHTML=reportTable(antiguedad_saldos,['saldo_pendiente']);
  });
}
export async function audit(el,ctx) {
  const {eventos}=await request('/auditoria/eventos');
  eventos.sort((a,b)=>Date.parse(b.timestamp)-Date.parse(a.timestamp));
  let page=0;
  function draw() {
    el.innerHTML='<h2>Eventos recuperados <small>'+eventos.length+'</small></h2>'+table(['Fecha y hora local','Usuario','Acción','Estado','Detalle'],eventos.slice(page*10,page*10+10).map((x,i)=>[
      esc(new Date(x.timestamp).toLocaleString('es-MX')),esc(x.id_usuario),esc(x.accion),badge(x.estado),button('detail','Ver evento',page*10+i)
    ]))+'<footer>Página '+(page+1)+' de '+Math.max(1,Math.ceil(eventos.length/10))+'<span>'+(page?button('prev','Anterior'):'')+((page+1)*10<eventos.length?button('next','Siguiente'):'')+'</span></footer>';
  }
  draw();
  ctx.actions(el,(action,id)=>{
    if (action==='detail') modal(eventos[id].accion,json(eventos[id].detalle));
    else {page+=action==='prev'?-1:1;draw();}
  });
}
export function users(el) {
  el.innerHTML='<h2>Registrar usuario</h2><div class="narrow"></div>';
  form(el.querySelector('.narrow'),field('nombre_completo','Nombre completo','text','maxlength="120"')+field('email','Correo electrónico','email','maxlength="120"')+field('password','Contraseña','password','minlength="8" autocomplete="new-password"')+select('rol','Rol de acceso',choices(['CLIENTE','OPERADOR','CONTADOR','ADMIN'])),'Crear usuario',async data=>{
    const result=await request('/auth/register','POST',data);
    el.querySelector('form').reset();notice('Usuario creado con ID '+result.id_usuario+'.');
  });
}
