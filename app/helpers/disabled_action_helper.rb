# いまは使えない操作と、その理由(デザインシステム DisabledAction、見直し第22回)。
# ボタンは消さずに灰色(aria-disabled)にし、横の (i) で理由を出す。理由の文はモデルが返す BlockedReason。
module DisabledActionHelper
  INFO_TIP_ACTIONS = "mouseenter->info-tip#enter mouseleave->info-tip#leave focusin->info-tip#focus focusout->info-tip#blur keydown.esc->info-tip#escape".freeze

  # 灰色のボタンと (i)。押しても何も起きず、理由が出る。
  def disabled_action(label, blocked, icon: nil, style: nil)
    id = info_tip_id
    button = tag.button(type: "button", class: "nb-btn", style:, aria: { disabled: true, describedby: id }, data: { action: "info-tip#toggle" }) do
      safe_join([ (icon(icon, size: :sm) if icon), label ].compact)
    end
    tag.span(class: "nb-disabled-action", data: { controller: "info-tip", action: INFO_TIP_ACTIONS }) { button + info_tip_parts(blocked, id) }
  end

  # (i) だけ。ボタンでない操作(チェックボックスなど)に添える。入力欄の aria-describedby に id を書く。
  def info_tip(blocked, id: info_tip_id)
    tag.span(class: "nb-info", data: { controller: "info-tip", action: INFO_TIP_ACTIONS }) { info_tip_parts(blocked, id) }
  end

  def info_tip_id = "why-#{SecureRandom.hex(4)}"

  private

  def info_tip_parts(blocked, id)
    trigger = tag.button("i", type: "button", class: "nb-info-tip", aria: { label: "使えない理由", expanded: false, controls: id, describedby: id },
                              data: { info_tip_target: "trigger", action: "info-tip#toggle" })
    lines = [ tag.span(blocked.title, class: "nb-tip-title"), tag.span(blocked.reason) ]
    if blocked.what.present? || blocked.link?
      link = link_to(blocked.link_label, blocked_reason_href(blocked.link_target)) if blocked.link?
      lines << tag.span(safe_join([ blocked.what, link ].compact, " "), class: "nb-tip-sub")
    end
    lines << tag.span(blocked.alternative, class: "nb-tip-sub") if blocked.alternative.present?
    trigger + tag.span(safe_join(lines), id:, class: "nb-tip", hidden: true, data: { info_tip_target: "tip" })
  end

  def blocked_reason_href(target) = target.is_a?(String) ? target : polymorphic_path(target)
end
