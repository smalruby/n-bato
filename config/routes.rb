Rails.application.routes.draw do
  post "undo" => "undo#undo", :as => :undo
  post "redo" => "undo#redo", :as => :redo
  get "history" => "undo#history", :as => :history
  get "changes" => "changes#index", :as => :changes
  post "ui_prefs/help" => "ui_prefs#help", :as => :help_pref
  patch "role" => "roles#update", :as => :role
  get "pickers/:source" => "pickers#show", :as => :picker, :constraints => {source: /accounts|departments/}
  post "assistant" => "assistant#create", :as => :assistant
  post "assistant/perform" => "assistant#perform", :as => :assistant_perform
  resources :fiscal_periods, only: [] do
    post :start_next, on: :collection
    post :reopen, on: :member
  end
  get "year/:year" => "working_years#switch", :as => :year_switch, :constraints => {year: /\d{4}/}

  # 手続き。手順の済みにする・対象外にする・済みを取り消すは、状態の変化を「作る」で表す(docs/adr/0008・0038)
  resources :procedures, only: %i[index show create] do
    resources :steps, only: %i[update], controller: "procedure_steps", param: :key do
      resources :status_changes, only: :create, module: :procedure_steps
    end
  end
  resource :session
  # パスキー(見直し第14回)
  resource :passkey_session, only: :create do
    post :options
  end
  resources :passkeys, only: %i[index create update destroy] do
    collection do
      post :registration_options
      post :verify_password
      post :verify_options
      post :verify
    end
  end
  resources :passwords, param: :token

  root "dashboard#show"

  resources :fiscal_years, only: %i[index show], param: :year do
    resources :statements, only: :show, param: :kind
    resources :ledgers, only: %i[index show], param: :account_code
    get "siwake", to: "journal_entries#export", as: :siwake_export
  end
  resources :journal_entries do
    # 取消(イベントを作る。docs/adr/0026)
    resource :cancellation, only: :create, module: :journal_entries
  end
  # やること(デザインシステム「やること」)。出来事(状態の変化・解決・送った・決めた)は、それぞれ「作る」で表す(docs/adr/0008・0034)
  resources :todos, only: %i[index show] do
    resources :status_changes, only: :create, module: :todos
  end
  resources :incoming_requests, only: %i[new create show] do
    resource :settlement, only: :create, module: :incoming_requests
    resource :cover_letter, only: :create, module: :incoming_requests
    resources :messages, controller: "incoming_request_messages", only: %i[create destroy] do
      resource :delivery, only: :create, module: :incoming_request_messages
      resource :adoption, only: :create, module: :incoming_request_messages
    end
  end
  # 決議。同意の取消・議案の反映は、それぞれ「作る」で表す(docs/adr/0008・0038)
  resources :resolutions do
    resources :consents, only: :create do
      resource :cancellation, only: :create, module: :consents
    end
    resources :items, only: [], controller: "resolution_items" do
      resource :application, only: :create, module: :resolution_items
    end
    get "documents/:doc", to: "resolutions#document", as: :document, on: :member
  end
  resources :registrations, only: %i[index]
  # 登記の申請(見直し第20回、docs/adr/0031)
  resources :registration_filings, only: %i[create show update] do
    post :include, on: :member
    post :exclude, on: :member
    get "documents/:doc", to: "registration_filings#document", as: :document, on: :member
    resource :submission, only: :create, module: :registration_filings
    resource :acceptance, only: :create, module: :registration_filings
    resource :completion, only: :create, module: :registration_filings
    resource :withdrawal, only: :create, module: :registration_filings
    resources :corrections, only: :create, module: :registration_filings
  end
  # 入会申込(デザインシステム「入会申込」)
  resources :member_applications, only: %i[index show] do
    resource :approval, only: :create, module: :member_applications
    resource :rejection, only: :create, module: :member_applications
  end
  resources :people do
    post :apply_to_years, on: :member
    resources :memberships, only: %i[create destroy]
    resources :officer_terms, only: %i[create destroy]
    # 住所が変わった・氏名が変わった(出来事を足す)と、その取消(docs/adr/0029)
    resources :address_changes, only: :create, module: :people
    resources :name_changes, only: :create, module: :people
    post "changes/:change_type/:change_id/cancellation", to: "people/change_cancellations#create", as: :change_cancellation
  end
  resources :annual_reports, param: :year, only: %i[index show new create edit update] do
    get "documents/:doc", to: "filings#show", as: :document, on: :member
    get "pack", to: "filings#pack", as: :pack, on: :member
  end
  resources :vouchers do
    post :propose, on: :member
    post :reject, on: :member
  end
  # AI の提案への出来事(イベント)は、それぞれ「作る」で表す(docs/adr/0008)
  resources :journal_proposals, only: [] do
    resource :approval, only: :create, module: :journal_proposals
    resource :rejection, only: :create, module: :journal_proposals
  end
  resources :siwake_imports, only: %i[index new create show destroy]
  resources :accounts, only: %i[index edit update] do
    post :apply_to_years, on: :member
  end
  resources :balance_checks, only: %i[index create destroy]
  resources :opening_balances, only: %i[index create destroy]
  resource :organization, only: %i[show edit update]
  # 提出先(見直し第17回、docs/adr/0027・0028)
  resources :filing_destinations, only: %i[index create update destroy] do
    resource :confirmation, only: :create, module: :filing_destinations
  end
  resources :filing_destination_searches, only: :create
  resource :filing_samples, only: :show
  resource :setup, only: %i[show update]
  resources :articles, only: %i[index show]
  resources :program_profiles, only: %i[update]

  get "up" => "rails/health#show", :as => :rails_health_check
end
