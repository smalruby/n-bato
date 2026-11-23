class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    mail subject: "Nばと: パスワードを決め直すリンク", to: user.email_address
  end
end
