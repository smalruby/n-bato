Rails.application.routes.draw do
  post "undo" => "undo#undo", as: :undo
  post "redo" => "undo#redo", as: :redo
  get "history" => "undo#history", as: :history
  get "changes" => "changes#index", as: :changes
  post "ui_prefs/help" => "ui_prefs#help", as: :help_pref
  patch "role" => "roles#update", as: :role
  get "pickers/:source" => "pickers#show", as: :picker, constraints: { source: /accounts|departments/ }
  post "assistant" => "assistant#create", as: :assistant
  post "assistant/perform" => "assistant#perform", as: :assistant_perform
  resources :fiscal_periods, only: [] do
    post :start_next, on: :collection
    post :reopen, on: :member
  end
  get "year/:year" => "working_years#switch", as: :year_switch, constraints: { year: /\d{4}/ }

  resources :procedures, only: %i[index show create] do
    resources :steps, only: %i[update], controller: "procedure_steps", param: :key do
      member do
        post :complete
        post :reopen
        post :skip
      end
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
  resources :journal_entries
  # やること(デザインシステム「やること」)
  resources :todos, only: %i[index update] do
    get :open, on: :member
  end
  resources :incoming_requests, only: %i[new create show] do
    post :resolve, on: :member
    post :cover_letter, on: :member
    resources :messages, controller: "incoming_request_messages", only: %i[create destroy] do
      post :deliver
      post :apply
    end
  end
  resources :resolutions do
    resources :consents, only: %i[create destroy]
    get "documents/:doc", to: "resolutions#document", as: :document, on: :member
    post "items/:item_id/apply", to: "resolutions#apply_item", as: :apply_item, on: :member
  end
  resources :registrations, only: %i[index update]
  # 入会申込(デザインシステム「入会申込」)
  resources :member_applications, only: %i[index show] do
    post :approve, on: :member
    post :reject, on: :member
  end
  resources :people do
    post :apply_to_years, on: :member
    resources :memberships, only: %i[create destroy]
    resources :officer_terms, only: %i[create destroy]
  end
  resources :annual_reports, param: :year, only: %i[index show new create edit update] do
    get "documents/:doc", to: "filings#show", as: :document, on: :member
    get "pack", to: "filings#pack", as: :pack, on: :member
  end
  resources :vouchers do
    post :propose, on: :member
    post :reject, on: :member
  end
  resources :journal_proposals, only: [] do
    post :approve, on: :member
    post :reject, on: :member
  end
  resources :siwake_imports, only: %i[index new create show destroy]
  resources :accounts, only: %i[index edit update] do
    post :apply_to_years, on: :member
  end
  resources :balance_checks, only: %i[index create destroy]
  resources :opening_balances, only: %i[index create destroy]
  resource :organization, only: %i[show edit update]
  resources :articles, only: %i[index show]
  resources :program_profiles, only: %i[update]

  get "up" => "rails/health#show", as: :rails_health_check
end
