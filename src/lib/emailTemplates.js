function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;')
}

function buildShell({ title, eyebrow, bodyHtml, footerNote }) {
  return `
  <div style="margin:0;padding:24px;background:#f3f6fb;font-family:Arial,Helvetica,sans-serif;color:#0f172a;">
    <div style="max-width:640px;margin:0 auto;background:#ffffff;border-radius:24px;overflow:hidden;border:1px solid #dbe4f0;box-shadow:0 14px 34px rgba(15,23,42,0.08);">
      <div style="background:linear-gradient(135deg,#0058A3 0%,#0A7BD8 100%);padding:28px 32px;color:#ffffff;">
        <div style="display:inline-block;background:#FFDA1A;color:#0f172a;border-radius:999px;padding:6px 12px;font-size:11px;font-weight:700;letter-spacing:0.16em;text-transform:uppercase;">${escapeHtml(eyebrow)}</div>
        <h1 style="margin:16px 0 8px;font-size:28px;line-height:1.2;">${escapeHtml(title)}</h1>
        <p style="margin:0;color:#dbeafe;font-size:14px;line-height:1.6;">IKEA Uniform Portal notification</p>
      </div>
      <div style="padding:32px;">
        ${bodyHtml}
      </div>
      <div style="padding:18px 32px;background:#f8fafc;border-top:1px solid #e2e8f0;color:#64748b;font-size:12px;line-height:1.6;">
        ${footerNote || 'This email was sent automatically by the IKEA Uniform Portal.'}
      </div>
    </div>
  </div>`
}

function buildSummaryGrid(rows) {
  return `
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:24px 0;">
      ${rows.map(({ label, value }) => `
        <div style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:16px;padding:14px 16px;">
          <div style="font-size:12px;text-transform:uppercase;letter-spacing:0.08em;color:#64748b;margin-bottom:6px;">${escapeHtml(label)}</div>
          <div style="font-size:15px;font-weight:700;color:#0f172a;line-height:1.4;">${escapeHtml(value || '—')}</div>
        </div>
      `).join('')}
    </div>
  `
}

export function buildNewRequestEmail(payload) {
  const statusTone = payload.status === 'pending' ? '#FFDA1A' : '#dbeafe'
  const textTone = payload.status === 'pending' ? '#1f2937' : '#0f172a'

  return buildShell({
    title: 'New uniform request received',
    eyebrow: 'New request',
    bodyHtml: `
      <p style="margin:0 0 16px;font-size:15px;line-height:1.7;color:#334155;">
        A new employee request has been submitted and is ready for admin review.
      </p>
      <div style="display:inline-block;background:${statusTone};color:${textTone};padding:10px 14px;border-radius:999px;font-size:13px;font-weight:700;text-transform:capitalize;">
        Status: ${escapeHtml(payload.status || 'pending')}
      </div>
      ${buildSummaryGrid([
        { label: 'Employee', value: payload.employee_name },
        { label: 'Email', value: payload.employee_email },
        { label: 'Product', value: payload.product_type },
        { label: 'Style', value: payload.style },
        { label: 'Colour', value: payload.colour },
        { label: 'Requested size', value: payload.requested_size },
        { label: 'Suggested size', value: payload.suggested_size || '—' },
        { label: 'Fulfillment mode', value: (payload.fulfillment_mode || 'pending').replaceAll('_', ' ') },
      ])}
      ${payload.notes ? `<div style="margin-top:18px;padding:16px;border-radius:18px;background:#fff8e1;border:1px solid #fde68a;"><div style="font-weight:700;color:#0f172a;margin-bottom:6px;">Employee notes</div><div style="font-size:14px;line-height:1.7;color:#475569;">${escapeHtml(payload.notes)}</div></div>` : ''}
    `,
  })
}

export function buildStatusChangeEmail(payload) {
  const status = (payload.status || '').toLowerCase()
  let badgeBackground = '#dbeafe'
  let badgeColor = '#0f172a'

  if (status === 'approved' || status === 'fulfilled') {
    badgeBackground = '#dcfce7'
    badgeColor = '#166534'
  } else if (status === 'pending' || status === 'ordered') {
    badgeBackground = '#FFDA1A'
    badgeColor = '#1f2937'
  } else if (status === 'rejected' || status === 'cancelled') {
    badgeBackground = '#fee2e2'
    badgeColor = '#991b1b'
  }

  return buildShell({
    title: 'Your request status changed',
    eyebrow: 'Status update',
    bodyHtml: `
      <p style="margin:0 0 16px;font-size:15px;line-height:1.7;color:#334155;">
        Hello <strong>${escapeHtml(payload.employee_name)}</strong>, your uniform request has been updated.
      </p>
      <div style="display:inline-block;background:${badgeBackground};color:${badgeColor};padding:10px 14px;border-radius:999px;font-size:13px;font-weight:700;text-transform:capitalize;">
        New status: ${escapeHtml(payload.status)}
      </div>
      ${buildSummaryGrid([
        { label: 'Product', value: payload.product_type },
        { label: 'Style', value: payload.style },
        { label: 'Colour', value: payload.colour },
        { label: 'Requested size', value: payload.requested_size },
        { label: 'Suggested size', value: payload.suggested_size || '—' },
      ])}
      ${payload.message ? `<div style="margin-top:18px;padding:16px;border-radius:18px;background:#f8fafc;border:1px solid #e2e8f0;"><div style="font-weight:700;color:#0f172a;margin-bottom:6px;">Admin note</div><div style="font-size:14px;line-height:1.7;color:#475569;">${escapeHtml(payload.message)}</div></div>` : ''}
      <p style="margin:20px 0 0;font-size:14px;line-height:1.7;color:#475569;">If you have questions, please contact your local P&amp;C team.</p>
    `,
  })
}
