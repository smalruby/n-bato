# 右ペイン「この画面の使い方」(デザインシステム HelpPanel)。中身は config/help/<画面>.yml。
module HelpHelper
  def help_content(screen = controller_name)
    @@help_cache ||= {}
    @@help_cache.delete(screen) if Rails.env.development?
    @@help_cache[screen] ||= begin
      path = Rails.root.join("config/help/#{screen}.yml")
      path = Rails.root.join("config/help/default.yml") unless path.exist?
      YAML.load_file(path)
    end
  end

  # いまの状態(上に出す説明の鍵)。画面が @help_states で足せる。
  def help_states
    states = Array(@help_states).map(&:to_s)
    states << "closed" if @working_period&.closed?
    states << "provisional" if @working_period&.provisional?
    states << "filtered" if @filter.respond_to?(:any?) && @filter.any?
    states.uniq
  end

  def help_collapsed?(screen = controller_name) = Current.user&.ui_prefs&.dig("help_collapsed", screen) == true
end
