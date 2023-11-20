import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction, DeployOptions } from 'hardhat-deploy/types';

const func: DeployFunction = async function(hre: HardhatRuntimeEnvironment) {
  const { deployments, getChainId, getNamedAccounts, network } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();
  const networkName = network.name;

  const chainId = await getChainId();
  const baseDeployArgs: DeployOptions = {
    from: deployer,
    log: true,
    skipIfAlreadyDeployed: networkName === 'evm',
  };

  console.log('chainId', chainId);
  console.log('networkName', networkName);

  await deploy('MultiSigFactory', {
    ...baseDeployArgs,
    args: [],
  });
};

export default func;
func.tags = ['MultiSig'];
