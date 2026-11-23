module MemberApplicationsHelper
  def member_application_tag(a)
    cls = { "received" => "nb-tag--soon", "approved" => "nb-tag--done", "rejected" => "nb-tag--plain" }[a.status]
    tag.span(a.status_label, class: "nb-tag #{cls}")
  end
end
