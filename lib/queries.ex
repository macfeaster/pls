defmodule Pls.Queries do
  import Ecto.Query

  def parse_group(group) do
    {group.name, Enum.map(group.permissions, &(&1.name))}
  end

  def user do
    Pls.Repo.all from(u in Pls.Repo.User, select: u.uid)
  end

  def user(uid) do
    dfunkt_group = Pls.Dfunkt.dfunkt_group uid
    dfunkt_permissions = from(g in Pls.Repo.Group,
      where: g.name |> like(^("%." <> dfunkt_group)),
      preload: :permissions)
    |> Pls.Repo.all
    |> Enum.map(&(%{&1 | name: &1.name |> String.split(".") |> Enum.drop(-1) |> Enum.join(".")})) # remove .xxx suffix from name

    from(u in Pls.Repo.User,
      where: u.uid == ^uid,
      preload: [groups: :permissions])
    |> Pls.Repo.all
    |> Enum.flat_map(&Map.get &1, :groups)
    |> Enum.concat(dfunkt_permissions)
    |> Enum.map(&parse_group &1)
    |> Enum.reduce(%{}, fn({name, permissions}, map) ->
        Map.update map, name, permissions, &Enum.uniq(Enum.concat &1, permissions)
      end)
  end

  def user(uid, group_name) do
    Map.get user(uid), group_name, false
  end

  def user(uid, group_name, permission) do
    permissions = user(uid, group_name)
    permissions && Enum.member? permissions, permission
  end

  def group do
    Pls.Repo.all from(g in Pls.Repo.Group, select: g.name)
  end

  def group(name) do
    group = from(g in Pls.Repo.Group,
      where: g.name == ^name,
      preload: [:permissions, [memberships: :user]])
    |> Pls.Repo.one

    if group == nil, do: raise Maru.Exceptions.NotFound

    %{
        permissions: Enum.map(group.permissions, &(&1.name)),
        memberships: Enum.map(group.memberships, &(%{name: &1.user.uid, expiry: &1.expiry}))
    }
  end

  def group(name, permission) do
    Enum.member? group(name), permission
  end

  def insert(change) do
    case Pls.Repo.insert change do
      {:ok, struct} -> struct
      {:error, change} -> Ecto.Changeset.traverse_errors change, fn {msg, _} -> msg end
    end
  end

  def delete(query) do
    case Pls.Repo.delete_all query do
      {res, nil} -> "Removed #{res} row(s)"
      {_, err}   -> err
    end
  end

  def add_user(uid) do
    insert Pls.Repo.User.new(uid)
  end
  def delete_user(uid) do
    delete from(g in Pls.Repo.User,
      where: g.uid == ^uid)
  end

  def add_group(name) do
    insert Pls.Repo.Group.new(name)
  end

  def delete_group(name) do
    delete from(g in Pls.Repo.Group,
      where: g.name == ^name)
  end

  def add_permission(group_name, permissions) when is_list(permissions) do
    Enum.map(permissions, fn(permission) -> add_permission(group_name, permission) end)
  end

  def add_permission(group_name, permission) do
    insert Pls.Repo.Permission.new(group_name, permission)
  end

  def delete_permission(group_name, permission) do
    group_id = Pls.Repo.one from(g in Pls.Repo.Group,
      where: g.name == ^group_name, select: g.id)

    delete from(p in Pls.Repo.Permission, 
      where: [group_id: ^group_id, name: ^permission])
  end

  def add_membership(uid, group_name, expiry) do
    insert Pls.Repo.Membership.new(uid, group_name, expiry)
  end

  def delete_membership(uid, group_name) do
    user = Pls.Repo.one from(u in Pls.Repo.User, where: u.uid == ^uid)
    group = Pls.Repo.one from(g in Pls.Repo.Group, where: g.name == ^group_name)

    delete from(m in Pls.Repo.Membership, where: [user_id:  ^user.id, group_id: ^group.id])
  end

  def clean do
    delete from(m in Pls.Repo.Membership, where: m.expiry < ^Ecto.Date.utc)
  end

end
