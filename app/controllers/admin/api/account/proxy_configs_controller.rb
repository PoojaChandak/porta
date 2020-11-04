# frozen_string_literal: true

class Admin::Api::Account::ProxyConfigsController < Admin::Api::BaseController
  include ApiAuthentication::BySsoToken

  represents :json, entity: ::ProxyConfigRepresenter
  represents :json, collection: ::ProxyConfigsRepresenter

  clear_respond_to
  respond_to :json

  rescue_from(ProxyConfig::InvalidEnvironmentError) do
    render_error 'invalid environment', status: :unprocessable_entity
  end

  self.default_per_page = 100

  ##~ e = sapi.apis.add
  ##~ e.path = "/admin/api/account/proxy_configs/{environment}.json"
  ##~ e.responseClass = "proxy_config"
  #
  ##~ op             = e.operations.add
  ##~ op.httpMethod  = "GET"
  ##~ op.summary     = "Proxy Configs List (Provider)"
  ##~ op.description = "Returns the Proxy Configs of the provider"
  ##~ op.group       = "proxy_config"
  #
  ##~ op.parameters.add @parameter_access_token
  ##~ op.parameters.add @parameter_environment
  #
  def index
    respond_with proxy_configs.order(:id).paginate(pagination_params)
  end

  private

  def proxy_configs
    @proxy_configs ||= ProxyConfig.where(proxy_id: accessible_proxies_ids).by_environment(environment).tap do |configs|
      configs.by_host(host) if host
    end
  end

  def accessible_proxies_ids
    @accessible_proxies_ids ||= begin
      accessible_services_ids = current_account.accessible_services.pluck(:id)
      accessible_services_ids = accessible_services_ids | current_user.member_permission_ids.to_a if current_user.present? # TODO: fix this Set vs Array stuff
      Proxy.where(service_id: accessible_services_ids).pluck(:id)
    end
  end

  def environment
    params.require(:environment)
  end

  def host
    params.permit(:host)
  end
end
