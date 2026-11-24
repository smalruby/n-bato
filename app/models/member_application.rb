# 入会申込(デザインシステム「入会申込」)。AI がフォームの回答から入れる。理事長が「入会を認める」を押すと、
# 人の記録とその年度の正会員の資格ができる(定款第7条)。認めた・認めないは詳細のイベント(docs/adr/0030)。住所・メール・電話は人の記録と同じく暗号化する。
class MemberApplication < ApplicationRecord
  encrypts :postal_code, :address, :email, :phone, :referral, :help_offers, :comments
  belongs_to :person, optional: true

  STATUSES = {"received" => "届いた", "approved" => "認めた", "rejected" => "認めない"}.freeze
  validates :name, :applied_on, presence: true
  validates :status, inclusion: {in: STATUSES.keys}

  scope :ordered, -> { order(Arel.sql("status = 'received' DESC"), applied_on: :desc, id: :desc) }
  scope :received, -> { where(status: "received") }

  def to_s = name
  def status_label = STATUSES[status]
  def received? = status == "received"
  def approved? = status == "approved"
  def rejected? = status == "rejected"
  def default_year = FiscalYear.for(applied_on).year
  def full_address = [postal_code.presence && "〒#{postal_code}", address].compact.join(" ")
  def same_name_people = Person.where(name:).or(Person.where(name: name.to_s.gsub(/[\s　]+/, "　"))).distinct

  has_one :approval, class_name: "MemberApplication::Approval", dependent: :restrict_with_error
  has_one :rejection, class_name: "MemberApplication::Rejection", dependent: :restrict_with_error

  # いまの状態は、認めた・認めないのイベントから決まる(docs/adr/0005・0030)。照合は model:verify。
  def derived_status
    if approval then "approved"
    elsif rejection then "rejected"
    else "received"
    end
  end

  # 入会のお知らせメールの下書き(n-bato からは送らない。理事長がコピーして送る)
  def welcome_mail
    org = Organization.current
    <<~MAIL
      件名: 正会員の入会について(#{org&.name})

      #{name} 様

      このたびは、#{org&.name}の正会員にお申し込みいただき、ありがとうございます。
      #{joined_on&.strftime("%Y年%-m月%-d日")}付けで、正会員として入会を認めましたので、お知らせします(定款第7条)。

      正会員の皆さまには、年 1 回の総会での議決や、議案への同意(書面決議)をお願いしています。
      ご案内が届きましたら、ご回答をよろしくお願いします。

      入会金はありません。年会費(5,000 円)は、2027年度からお支払いをお願いする予定です。あらためてお知らせします。

      ご不明な点は、このメールへの返信でお問い合わせください。

      #{org&.name}
      #{org&.representative_title} #{org&.representative_name}
    MAIL
  end
end
