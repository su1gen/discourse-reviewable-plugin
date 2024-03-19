# frozen_string_literal: true

module UpgradedReviewables
  module ReviewablesControllerExtension
    def self.prepended(base)
      base.class_eval do
        before_action :ensure_can_see, except: [:destroy, :updated_reviewable]
      end
    end

    def update
      reviewable = find_reviewable
      if error = claim_error?(reviewable)
        return render_json_error(error)
      end

      editable = reviewable.editable_for(guardian)
      raise Discourse::InvalidAccess.new unless editable.present?

      # Validate parameters are all editable
      edit_params = params[:reviewable] || {}
      edit_params.each do |name, value|
        if value.is_a?(ActionController::Parameters)
          value.each do |pay_name, pay_value|
            raise Discourse::InvalidAccess.new unless editable.has?("#{name}.#{pay_name}")
          end
        else
          raise Discourse::InvalidAccess.new unless editable.has?(name)
        end
      end

      begin
        if reviewable.update_fields(edit_params, current_user, version: params[:version].to_i)
          result = edit_params.merge(version: reviewable.version)
          if reviewable.topic_id.present?
            MessageBus.publish("/reviewable-update/#{reviewable.topic_id}", {
              action: 'edit',
              reviewable_id: reviewable.id
            })
          end
          render json: result
        else
          render_json_error(reviewable.errors)
        end
      rescue Reviewable::UpdateConflict
        render_json_error(I18n.t("reviewables.conflict"), status: 409)
      end
    end

    def perform
      args = { version: params[:version].to_i }

      result = nil
      begin
        reviewable = find_reviewable

        if error = claim_error?(reviewable)
          return render_json_error(error)
        end

        if reviewable.type_class.respond_to?(:additional_args)
          args.merge!(reviewable.type_class.additional_args(params) || {})
        end

        plugin_params =
          DiscoursePluginRegistry.reviewable_params.select do |reviewable_param|
            reviewable.type == reviewable_param[:type].to_s.classify
          end
        args.merge!(params.slice(*plugin_params.map { |pp| pp[:param] }).permit!)

        result = reviewable.perform(current_user, params[:action_id].to_sym, args)
      rescue Reviewable::InvalidAction => e
        if reviewable.type == "ReviewableUser" && !reviewable.pending? && reviewable.target.blank?
          raise Discourse::NotFound.new(
            e.message,
            custom_message: "reviewables.already_handled_and_user_not_exist",
            )
        else
          # Consider InvalidAction an InvalidAccess
          raise Discourse::InvalidAccess.new(e.message)
        end
      rescue Reviewable::UpdateConflict
        return render_json_error(I18n.t("reviewables.conflict"), status: 409)
      end

      if result.success?
        if reviewable.type == "ReviewableQueuedPost" && reviewable.topic_id.present? && (params[:action_id] == 'approve_post' || params[:action_id] == 'reject_post')
          MessageBus.publish("/reviewable-update/#{reviewable.topic_id}", {
            action: 'delete',
            reviewable_id: reviewable.id
          })
        end
        render_serialized(result, ReviewablePerformResultSerializer)
      else
        render_json_error(result)
      end
    end

    def updated_reviewable
      reviewable = Reviewable.find(params[:reviewable_id].to_i)
      render json: reviewable, only: [:reviewable_queued_post]
    end
  end
end
