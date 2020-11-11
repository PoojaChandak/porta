# frozen_string_literal: true

class FetchProxyConfigsService
  # TODO: too many params
  def initialize(environment:, host: nil, version: nil, watcher: nil, owner:)
    # watcher being the user/account who does the request (to check the permissions!)
    # owner being either the service that owns the proxy configs or the tenant who does

    @environment = environment
    @host = host
    @version = version
    @watcher = watcher
    @owner = owner
  end

  # TODO: maybe memoize because this is for the same params always (inside the same instance!)
  def call
    ProxyConfig
      .where(proxy_id: proxy_ids)
      .by_environment(environment)
      .by_host(host)
      .by_version(version)
  end

  private

  attr_reader :environment, :host, :version, :watcher, :owner

  def proxy_ids
    Proxy.where(service_id: service_ids).pluck(:id)
  end

  def service_ids
    accessible_services_ids & member_permission_service_ids
  end

  def accessible_services_ids
    case owner
    when Account then owner.accessible_services.pluck(:id)
    when Service then [owner.id]
    else []
    end
  end

  def member_permission_service_ids
    ids = watcher.try(:forbidden_some_services?) ? watcher.member_permission_service_ids : nil
    ids || accessible_services_ids
  end
end
