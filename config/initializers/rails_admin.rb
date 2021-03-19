require 'rails_admin/config/actions/redact_queue'
require 'rails_admin/config/actions/redact_notice'
require 'rails_admin/config/actions/pdf_requests'
require 'rails_admin/config/actions/approve_api_submitter_request'
require 'rails_admin/config/actions/reject_api_submitter_request'
require 'rails_admin/config/fields/types/datetime_timezoned'

RailsAdmin.config do |config|
  config.parent_controller = '::ApplicationController'

  config.main_app_name = ['Lumen Database', 'Admin']

  config.current_user_method { current_user }

  config.authorize_with :cancancan

  config.audit_with :history, 'User'
  config.audit_with :history, 'Role'
  config.audit_with :history, 'Notice'

  boolean_true_icon = '<span class="label label-success">&#x2713;</span>'.html_safe
  boolean_false_icon = '<span class="label label-danger">&#x2718;</span>'.html_safe

  config.actions do
    dashboard do
      statistics false
    end

    # collection-wide actions
    index
    new
    export
    history_index
    bulk_delete

    # member actions
    show
    edit
    delete
    history_show
    show_in_app

    init_actions!

    redact_queue
    redact_notice
    pdf_requests

    approve_api_submitter_request
    reject_api_submitter_request
  end

  ['Notice', Notice::TYPES].flatten.each do |notice_type|
    config.audit_with :history, notice_type

    config.model notice_type do
      label { abstract_model.model.label }

      list do
        # SELECT COUNT is slow when the number of instances is large; let's
        # avoid calling it for Notice and its subclasses.
        limited_pagination true

        field :id
        field :title
        field(:date_sent)     { label 'Sent' }
        field(:date_received) { label 'Received' }
        field(:created_at)    { label 'Submitted' }
        field(:original_notice_id) { label 'Legacy NoticeID' }
        field :source
        field :review_required
        field :published
        field :time_to_publish
        field :body
        field :entities
        field :topics
        field :works
        field :url_count
        field :action_taken
        field :reviewer_id
        field :language
        field :rescinded
        field :type
        field :spam
        field :hidden
        field :request_type
        field :webform
      end

      show do
        configure(:infringing_urls) { hide }
        configure(:copyrighted_urls) { hide }
        configure(:token_urls) { hide }
        configure(:restricted_to_researchers) do
          formatted_value do
            bindings[:object].restricted_to_researchers? ? boolean_true_icon : boolean_false_icon
          end
        end
      end

      edit do
        # This dramatically speeds up the admin page.
        configure :works do
          nested_form false
        end

        configure :action_taken, :enum do
          enum do
            %w[Yes No Partial Unspecified]
          end
          default_value 'Unspecified'
        end

        configure(:type) do
          hide
        end
        configure :reset_type, :enum do
          label 'Type'
          required true
        end

        exclude_fields :topic_assignments,
                       :topic_relevant_questions,
                       :infringing_urls,
                       :copyrighted_urls,
                       :token_urls

        configure :review_required do
          visible do
            ability = Ability.new(bindings[:view]._current_user)
            ability.can? :publish, Notice
          end
        end

        configure :rescinded do
          visible do
            ability = Ability.new(bindings[:view]._current_user)
            ability.can? :rescind, Notice
          end
        end
      end
    end
  end

  config.model 'Topic' do
    list do
      field :id
      field :name
      field :parent do
        formatted_value do
          parent = bindings[:object].parent
          parent && "#{parent.name} - ##{parent.id}"
        end
      end
    end
    edit do
      # exclude_fields :notices might be a better performance option than hide,
      # but it prevents topics with null ancestries from being saved.
      configure(:notices) { hide }
      configure(:topic_assignments) { hide }

      configure :parent_id, :enum do
        enum_method do
          :parent_enum
        end
      end
    end
  end

  config.model 'EntityNoticeRole' do
    edit do
      configure(:notice) { hide }
      configure :entity do
        nested_form false
      end
    end
  end

  config.model 'Entity' do
    list do
      # See exclude_fields comment for Topic.
      exclude_fields :notices
      configure(:entity_notice_roles) { hide }
      configure :parent do
        formatted_value do
          parent = bindings[:object].parent
          parent && "#{parent.name} - ##{parent.id}"
        end
      end
    end
    edit do
      configure :kind, :enum do
        enum do
          %w[individual organization]
        end
        default_value 'organization'
      end
      configure(:notices) { hide }
      configure(:entity_notice_roles) { hide }
      configure(:ancestry) { hide }
      # Unfortunately, there are too many entities to make parents editable
      # via default rails_admin functionality.
      # configure :parent_id, :enum do
      #   enum_method do
      #     :parent_enum
      #   end
      # end
    end
  end

  config.model 'RelevantQuestion' do
    object_label_method { :question }
  end

  config.model 'Work' do
    object_label_method { :custom_work_label }

    edit do
      configure(:notices) { hide }
    end

    list do
      limited_pagination true
      configure(:copyrighted_urls) { hide }
      configure(:infringing_urls) { hide }
    end

    nested do
      configure(:infringing_urls) { hide }
      configure(:copyrighted_urls) { hide }
    end
  end

  config.model 'InfringingUrl' do
    object_label_method { :url }

    list do
      limited_pagination true
    end
  end

  config.model 'FileUpload' do
    edit do
      configure :kind, :enum do
        enum do
          %w[original supporting]
        end
      end
    end
  end

  config.model 'ReindexRun' do
  end

  def custom_work_label
    %Q(#{self.id}: #{self.description && self.description[0,30]}...)
  end

  config.model 'User' do
    object_label_method { :email }
    edit do
      configure :entity do
        nested_form false
      end
      configure(:token_urls) { hide }
    end
  end

  config.model 'TokenUrl' do
    configure :url do
      formatted_value do
        url = "#{Chill::Application.config.site_host}/notices/#{bindings[:object].notice_id}?access_token=#{bindings[:object].token}"
        %(<a href="//#{url}">#{bindings[:object].token}</a>).html_safe
      end
      visible false
    end

    list do
      field :url
      field :email
      field :user
      field :notice
      field :expiration_date
      field :valid_forever
      field :created_at
    end

    edit do
      field :email do
        required false
      end
      field :user
      field :notice do
        required true
      end
      field :expiration_date
      field :valid_forever
      field :documents_notification
    end
  end

  config.model 'RiskTriggerCondition' do
    edit do
      configure :field, :enum do
        enum do
          RiskTriggerCondition::ALLOWED_FIELDS.sort
        end
      end
      configure :matching_type, :enum do
        enum do
          RiskTriggerCondition::ALLOWED_MATCHING_TYPES
        end
      end
    end
  end

  config.model 'RiskTrigger' do
    edit do
      configure :matching_type, :enum do
        enum do
          RiskTrigger::ALLOWED_MATCHING_TYPES
        end
      end
    end
  end

  config.model 'ApiSubmitterRequest' do
    list do
      field :id
      field :email
      field :entity_name
      field :entity_url
      field :user
      field :approved
    end

    edit do
      field :email
      field :entity_url
      field :description
      field :admin_notes
      field :entity_name
      field :entity_kind
      field :entity_address_line_1
      field :entity_address_line_2
      field :entity_state
      field :entity_country_code
      field :entity_phone
      field :entity_url
      field :entity_email
      field :entity_city
      field :entity_zip
      field :user
    end
  end
end
