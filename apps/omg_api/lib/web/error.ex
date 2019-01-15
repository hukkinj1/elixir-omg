# Copyright 2018 OmiseGO Pte Ltd
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule OMG.API.Web.Error do
  @moduledoc """
  Provides standard data structure for API Error response
  """

  @doc """
  Serializes error's code and description provided in response's data field.
  """
  @spec serialize(atom() | String.t(), String.t() | nil) :: map()
  def serialize(code, description) do
    %{
      object: :error,
      code: code,
      description: description
    }
    |> OMG.API.Web.Response.serialize()
  end
end
