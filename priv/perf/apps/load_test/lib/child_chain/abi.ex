# Copyright 2019-2020 OmiseGO Pte Ltd
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

defmodule LoadTest.ChildChain.Abi do
  alias ExPlasma.Encoding
  alias LoadTest.ChildChain.Abi.AbiEventSelector
  alias LoadTest.ChildChain.Abi.Fields

  def decode_log(log) do
    event_specs =
      Enum.reduce(AbiEventSelector.module_info(:exports), [], fn
        {:module_info, 0}, acc -> acc
        {function, 0}, acc -> [apply(AbiEventSelector, function, []) | acc]
        _, acc -> acc
      end)

    topics =
      Enum.map(log["topics"], fn
        nil -> nil
        topic -> Encoding.to_binary(topic)
      end)

    data = Encoding.to_binary(log["data"])

    {event_spec, data} =
      ABI.Event.find_and_decode(
        event_specs,
        Enum.at(topics, 0),
        Enum.at(topics, 1),
        Enum.at(topics, 2),
        Enum.at(topics, 3),
        data
      )

    data
    |> Enum.into(%{}, fn {key, _type, _indexed, value} -> {key, value} end)
    |> Fields.rename(event_spec)
    |> common_parse_event(log)
  end

  def common_parse_event(
        result,
        %{"blockNumber" => eth_height, "transactionHash" => root_chain_txhash, "logIndex" => log_index} = event
      ) do
    # NOTE: we're using `put_new` here, because `merge` would allow us to overwrite data fields in case of conflict
    result
    |> Map.put_new(:eth_height, Encoding.to_int(eth_height))
    |> Map.put_new(:root_chain_txhash, Encoding.to_binary(root_chain_txhash))
    |> Map.put_new(:log_index, Encoding.to_int(log_index))
    # just copy `event_signature` over, if it's present (could use tidying up)
    |> Map.put_new(:event_signature, event[:event_signature])
  end
end