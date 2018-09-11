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

defmodule OMG.Watcher.Web.Controller.UtxoTest do
  use ExUnitFixtures
  use ExUnit.Case, async: false
  use OMG.API.Fixtures

  alias OMG.API
  alias OMG.API.Block
  alias OMG.API.Crypto
  alias OMG.API.TestHelper
  alias OMG.API.Utxo
  alias OMG.Watcher.TestHelper
  alias OMG.Watcher.TransactionDB
  alias OMG.Watcher.TxOutputDB
  alias OMG.Watcher.EthEventDB

  require Utxo

  @eth Crypto.zero_address()
  @eth_hex String.duplicate("00", 20)

  describe "Controller.UtxoTest" do
    @tag fixtures: [:phoenix_ecto_sandbox, :alice]
    test "No utxo are returned for non-existing addresses.", %{alice: alice} do
      {:ok, alice_address_encode} = Crypto.encode_address(alice.addr)

      expected_result = %{
        "result" => "success",
        "data" => %{
          "address" => alice_address_encode,
          "utxos" => []
        }
      }

      assert expected_result == get_utxos(alice.addr)
    end

    @tag fixtures: [:phoenix_ecto_sandbox, :alice]
    test "Consumed block contents are available.", %{alice: alice} do
      TransactionDB.update_with(%Block{
        transactions: [
          API.TestHelper.create_recovered([], @eth, [{alice, 1947}]),
          API.TestHelper.create_recovered([], @eth, [{alice, 1952}, {alice, 1900}])
        ],
        number: 2000
      })

      {:ok, alice_address_encode} = Crypto.encode_address(alice.addr)
      %{
        "result" => "success",
        "data" => %{
          "address" => ^alice_address_encode,
          "utxos" => utxos
        }
      } = get_utxos(alice.addr)

      assert length(utxos) == 3

      # disregard `txbytes` which is going away anyway
      utxos = Enum.map(utxos, &Map.delete(&1, "txbytes"))

      assert %{"currency" => @eth_hex, "amount" => 1947, "blknum" => 2, "txindex" => 0, "oindex" => 0} in utxos
      assert %{"currency" => @eth_hex, "amount" => 1952, "blknum" => 2, "txindex" => 1, "oindex" => 0} in utxos
      assert %{"currency" => @eth_hex, "amount" => 1900, "blknum" => 2, "txindex" => 1, "oindex" => 1} in utxos
    end

    @tag fixtures: [:phoenix_ecto_sandbox, :alice, :bob, :carol]
    test "Spent utxos are moved to new owner.", %{alice: alice, bob: bob, carol: carol} do
      TransactionDB.update_with(%Block{
        transactions: [
          API.TestHelper.create_recovered([], @eth, [{alice, 1843}]),
          API.TestHelper.create_recovered([], @eth, [{bob, 1871}, {bob, 1872}])
        ],
        number: 1000
      })

      {:ok, bob_address_encode} = Crypto.encode_address(bob.addr)
      assert %{
               "result" => "success",
               "data" => %{
                 "address" => ^bob_address_encode,
                 "utxos" => [%{"amount" => 1871}, %{"amount" => 1872}]
               }
             } = get_utxos(bob.addr)

      TransactionDB.update_with(%Block{
        transactions: [API.TestHelper.create_recovered([{1000, 1, 0, bob}, {1000, 1, 1, bob}], @eth, [{carol, 1000}])],
        number: 2000
      })

      {:ok, carol_address_encode} = Crypto.encode_address(carol.addr)
      assert %{
               "result" => "success",
               "data" => %{
                 "address" => ^carol_address_encode,
                 "utxos" => [%{"amount" => 1000}]
               }
             } = get_utxos(carol.addr)

      assert %{
               "result" => "success",
               "data" => %{
                 "address" => ^bob_address_encode,
                 "utxos" => []
               }
             } = get_utxos(bob.addr)
    end

    @tag fixtures: [:phoenix_ecto_sandbox, :alice]
    test "Deposits are a part of utxo set.", %{alice: alice} do
      {:ok, alice_address_encode} = Crypto.encode_address(alice.addr)

      assert %{
               "result" => "success",
               "data" => %{
                 "address" => ^alice_address_encode,
                 "utxos" => []
               }
             } = get_utxos(alice.addr)

      EthEventDB.insert_deposits([%{owner: alice.addr, currency: @eth, amount: 1, blknum: 1, hash: "hash1"}])

      assert %{
               "result" => "success",
               "data" => %{
                 "address" => ^alice_address_encode,
                 "utxos" => [%{"amount" => 1, "currency" => @eth_hex}]
               }
             } = get_utxos(alice.addr)
    end

    @tag fixtures: [:phoenix_ecto_sandbox, :alice, :bob]
    test "Deposit utxo are moved to new owner if spent ", %{alice: alice, bob: bob} do
      {:ok, alice_address_encode} = Crypto.encode_address(alice.addr)
      {:ok, bob_address_encode} = Crypto.encode_address(bob.addr)

      assert %{
               "result" => "success",
               "data" => %{
                 "address" => ^alice_address_encode,
                 "utxos" => []
               }
             } = get_utxos(alice.addr)

      assert %{
               "result" => "success",
               "data" => %{
                 "address" => ^bob_address_encode,
                 "utxos" => []
               }
             } = get_utxos(bob.addr)

      EthEventDB.insert_deposits([%{owner: alice.addr, currency: @eth, amount: 1, blknum: 1, hash: "hash1"}])

      assert %{
               "result" => "success",
               "data" => %{
                 "address" => ^alice_address_encode,
                 "utxos" => [%{"amount" => 1}]
               }
             } = get_utxos(alice.addr)

      TransactionDB.update_with(%Block{
        transactions: [API.TestHelper.create_recovered([{1, 0, 0, alice}], @eth, [{bob, 1}])],
        number: 2000
      })

      assert %{
               "result" => "success",
               "data" => %{
                 "address" => ^alice_address_encode,
                 "utxos" => []
               }
             } = get_utxos(alice.addr)

      assert %{
               "result" => "success",
               "data" => %{
                 "address" => ^bob_address_encode,
                 "utxos" => [%{"amount" => 1}]
               }
             } = get_utxos(bob.addr)
    end
  end

  @tag fixtures: [:phoenix_ecto_sandbox, :alice]
  test "utxo/:utxo_pos/exit_data endpoint returns proper response format", %{alice: alice} do
    TransactionDB.update_with(%Block{
      transactions: [
        API.TestHelper.create_recovered([], @eth, [{alice, 120}]),
        API.TestHelper.create_recovered([], @eth, [{alice, 110}]),
        API.TestHelper.create_recovered([], @eth, [{alice, 100}])
      ],
      number: 1000
    })

    utxo_pos = Utxo.position(1000, 1, 0) |> Utxo.Position.encode()

    %{
      "data" => %{
        "utxo_pos" => _utxo_pos,
        "txbytes" => _txbytes,
        "proof" => proof,
        "sigs" => _sigs
      },
      "result" => "success"
    } = TestHelper.rest_call(:get, "/utxo/#{utxo_pos}/exit_data")

    assert <<_proof::bytes-size(1024)>> = proof
  end

  @tag fixtures: [:phoenix_ecto_sandbox]
  test "utxo/:utxo_pos/exit_data endpoint returns error when there is no txs in specfic block" do
    utxo_pos = Utxo.position(1, 1, 0) |> Utxo.Position.encode()

    assert %{
             "data" => %{
               "code" => "internal_server_error",
               "description" => "no_tx_for_given_blknum"
             },
             "result" => "error"
           } = TestHelper.rest_call(:get, "/utxo/#{utxo_pos}/exit_data", nil, 500)
  end

  @tag fixtures: [:phoenix_ecto_sandbox, :alice]
  test "utxo/:utxo_pos/exit_data endpoint returns error when there is no tx in specfic block", %{alice: alice} do
    TransactionDB.update_with(%Block{
      transactions: [
        API.TestHelper.create_recovered([{1, 0, 0, alice}], @eth, [{alice, 120}]),
        API.TestHelper.create_recovered([{1, 1, 0, alice}], @eth, [{alice, 110}]),
        API.TestHelper.create_recovered([{2, 0, 0, alice}], @eth, [{alice, 100}])
      ],
      number: 1000
    })

    utxo_pos = Utxo.position(1, 4, 0) |> Utxo.Position.encode()

    assert %{
             "data" => %{
               "code" => "internal_server_error",
               "description" => "no_tx_for_given_blknum"
             },
             "result" => "error"
           } = TestHelper.rest_call(:get, "/utxo/#{utxo_pos}/exit_data", nil, 500)
  end

  defp get_utxos(address) do
    {:ok, address_encode} = Crypto.encode_address(address)
    TestHelper.rest_call(:get, "/utxos?address=#{address_encode}")
  end
end
